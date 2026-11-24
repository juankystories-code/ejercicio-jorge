# Práctica 2 SGE – Odoo 19 Community nativo en Ubuntu Server 24.04

**Enunciado:** Instala PostgreSQL 16 y Odoo 19 Community en Ubuntu Server 24.04. Administra el servidor desde Windows mediante SSH y configura Nginx para acceder a Odoo mediante HTTPS. Utiliza los apartados 4, 5 y 6 del tema como referencia.

> Guía de trabajo. Los bloques **"Para el informe"** son texto ya redactado para pegar en la plantilla.
> Los bloques de comandos son para ejecutar. Donde pone 📸 hay que hacer captura.
> Sustituye `TU_USUARIO`, `TU_NOMBRE` y `NOMBRE_VM` por tus valores.

---

## 0. Preparación en Windows (antes de empezar)

### Qué necesitas tener en local

| Qué | Dónde se consigue |
|---|---|
| ISO de **Ubuntu Server 24.04** (`ubuntu-24.04.x-live-server-amd64.iso`, ~3 GB) | https://releases.ubuntu.com/24.04/ |
| **VirtualBox** | https://www.virtualbox.org/wiki/Downloads |
| Cliente **SSH** | Viene en Windows 10/11 (`ssh -V` en PowerShell) |
| Plantilla Nginx **`odoo_ua2`** y **plantilla del informe** | Plataforma del curso (la tarea) |

PostgreSQL, Odoo y Nginx **no** se descargan en Windows: se instalan dentro de Ubuntu con `apt` (apartados 2 y 6).

### Descarga automática

Desde PowerShell, en la carpeta del repositorio:

```bash
powershell -ExecutionPolicy Bypass -File .\descargar_requisitos.ps1
```

El script descarga la última ISO de Ubuntu Server 24.04 en `Descargas\SGE_P2`, comprueba su huella SHA256 (que no esté corrupta), instala VirtualBox con `winget` y revisa el cliente SSH y la virtualización.

### Crear la máquina virtual

- Tipo: Linux / Ubuntu (64-bit). **Marca "Omitir instalación desatendida"** para instalar tú a mano.
- RAM: 4096 MB · CPU: 2 · Disco: 25 GB (dinámico).
- Red: Adaptador 1 en **NAT**.
- En el instalador de Ubuntu: idioma, teclado **Spanish**, instalación "Ubuntu Server" normal, disco entero, crea tu usuario y **marca "Install OpenSSH server"** (te ahorra parte del apartado 1). No marques ningún snap extra.

📸 Captura de la configuración de la VM y del final de la instalación.

---

## 1. NAT y conexión por SSH

### Para el informe – ¿Qué es NAT?

**NAT (Network Address Translation, traducción de direcciones de red)** es una técnica por la que un equipo intermedio cambia las direcciones IP y puertos de los paquetes que pasan por él. Es lo mismo que hace el router de casa: todos los dispositivos salen a Internet con una única IP pública, y el router recuerda qué conexión pertenece a cada uno.

En VirtualBox, el modo **NAT** hace que el propio VirtualBox actúe como ese router para la máquina virtual:

- La VM recibe una IP privada (normalmente `10.0.2.15`), con puerta de enlace `10.0.2.2` y DNS `10.0.2.3`. Esa red solo existe dentro de VirtualBox.
- Cuando Ubuntu sale a Internet, VirtualBox reescribe los paquetes para que salgan como si fueran del propio Windows. Por eso la VM tiene Internet sin configurar nada.
- Lo contrario no funciona por defecto: desde Windows (o desde fuera) **no se puede iniciar una conexión** hacia la VM, porque `10.0.2.15` no es visible desde fuera de VirtualBox.

### Para el informe – Redirección de puertos

La **redirección de puertos (port forwarding)** es la regla que abre ese camino de entrada: "todo lo que llegue al puerto X del anfitrión, mándalo al puerto Y del invitado".

- **Puerto del anfitrión**: el puerto de Windows en el que VirtualBox se queda escuchando (por ejemplo `2222`). Es al que te conectas desde Windows usando `127.0.0.1`/`localhost`.
- **Puerto del invitado**: el puerto real del servicio dentro de Ubuntu (por ejemplo `22`, donde escucha OpenSSH).

Se usan puertos distintos en Windows (2222, 18069, 18080, 18443) para no chocar con servicios que ya usen 22, 80 o 443 en Windows y porque en Windows los puertos <1024 suelen necesitar permisos de administrador.

Ejemplo: `ssh -p 2222 usuario@127.0.0.1` → VirtualBox recibe en Windows:2222 → lo reenvía a Ubuntu:22 → responde OpenSSH.

### Configurar NAT y la regla SSH

Interfaz gráfica: **VM → Configuración → Red → Adaptador 1 → Conectado a: NAT → Avanzadas → Reenvío de puertos → ➕**

| Nombre | Protocolo | IP anfitrión | Puerto anfitrión | IP invitado | Puerto invitado |
|---|---|---|---|---|---|
| SSH | TCP | (vacío o 127.0.0.1) | 2222 | (vacío) | 22 |

📸 Captura del adaptador en NAT y de la tabla de reenvío.

(Alternativa desde PowerShell de Windows, con la VM apagada:)

```bash
"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" modifyvm "NOMBRE_VM" --natpf1 "SSH,tcp,,2222,,22"
```

### Comprobar conectividad en Ubuntu

```bash
ip -br a
```

```bash
ip route
```

```bash
ping -c 4 8.8.8.8
```

```bash
ping -c 4 ubuntu.com
```

📸 Se debe ver la IP `10.0.2.15`, la ruta por defecto vía `10.0.2.2` y que los pings responden (el segundo demuestra que el DNS funciona).

### Preparar OpenSSH

```bash
sudo apt update
```

```bash
sudo apt install -y openssh-server
```

```bash
sudo systemctl enable --now ssh
```

```bash
systemctl status ssh --no-pager
```

```bash
sudo ss -tlnp | grep :22
```

📸 Servicio `active` y escuchando en el 22.

### Conectar desde Windows (PowerShell o Terminal)

```bash
ssh -p 2222 TU_USUARIO@127.0.0.1
```

La primera vez pregunta si confías en la huella (fingerprint) del servidor → `yes`. 📸

### Crear carpetas y archivos (dentro de la sesión SSH)

```bash
mkdir -p ~/ua2_p2/config ~/ua2_p2/pruebas
```

```bash
cd ~/ua2_p2/pruebas
```

```bash
printf "TU_NOMBRE\nPráctica 2 de SGE\n" > terminal.txt
```

```bash
cp terminal.txt terminal_copia.txt
```

```bash
pwd && ls -l && cat terminal.txt terminal_copia.txt
```

```bash
tree ~/ua2_p2 || ls -R ~/ua2_p2
```

📸 Captura de la terminal de Windows mostrando todo (que se vea que es la sesión SSH).

---

## 2. PostgreSQL 16 y Odoo 19 Community

> En **Ubuntu Server 24.04** el paquete `postgresql` de los repositorios oficiales es la versión 16, así que no hace falta añadir repositorios extra. Compruébalo con `lsb_release -a` (captura para el informe).

```bash
sudo apt update && sudo apt upgrade -y
```

```bash
sudo apt install -y postgresql
```

Repositorio oficial de Odoo 19 (paquetes .deb):

```bash
wget -qO- https://nightly.odoo.com/odoo.key | sudo gpg --dearmor -o /usr/share/keyrings/odoo-archive-keyring.gpg
```

```bash
echo 'deb [signed-by=/usr/share/keyrings/odoo-archive-keyring.gpg] https://nightly.odoo.com/19.0/nightly/deb/ ./' | sudo tee /etc/apt/sources.list.d/odoo.list
```

```bash
sudo apt update && sudo apt install -y odoo
```

### Versiones y estado

```bash
psql --version
```

```bash
dpkg -l | grep -E "^ii\s+(odoo|postgresql-16) "
```

```bash
odoo --version
```

```bash
pg_lsclusters
```

```bash
sudo ss -tlnp | grep 5432
```

```bash
sudo systemctl enable postgresql odoo
```

```bash
systemctl is-enabled postgresql odoo
```

```bash
systemctl status odoo --no-pager
```

```bash
systemctl status postgresql@16-main --no-pager
```

```bash
sudo journalctl -u odoo -n 30 --no-pager
```

```bash
sudo journalctl -u postgresql@16-main -n 30 --no-pager
```

```bash
sudo tail -n 30 /var/log/postgresql/postgresql-16-main.log
```

```bash
sudo tail -n 30 /var/log/odoo/odoo-server.log
```

📸 `pg_lsclusters` debe mostrar `16 main 5432 online`.

**Fíjate:** `journalctl -u odoo` muestra muy poco porque el servicio del paquete arranca Odoo con `--logfile /var/log/odoo/odoo-server.log` (lo verás en `systemctl cat odoo`). El log útil está en ese archivo.

### Error típico y cómo corregirlo

Si en el log de Odoo aparece `role "odoo" does not exist` o `FATAL: Peer authentication failed`, falta el usuario `odoo` en PostgreSQL:

```bash
sudo -u postgres psql -c "\du"
```

```bash
sudo -u postgres createuser --createdb --no-superuser --no-createrole odoo
```

```bash
sudo systemctl restart odoo && sudo tail -n 20 /var/log/odoo/odoo-server.log
```

Documenta en el informe el error, la causa y el resultado tras corregirlo (si no te sale ningún error, indícalo y muestra los logs limpios).

---

## 3. Configurar Odoo y crear la base de datos

```bash
systemctl cat odoo | grep ExecStart
```

(Confirma que el archivo es `/etc/odoo/odoo.conf`.)

```bash
sudo cp /etc/odoo/odoo.conf /etc/odoo/odoo.conf.p2.bak
```

```bash
sudo cat /etc/odoo/odoo.conf
```

Edita:

```bash
sudo nano /etc/odoo/odoo.conf
```

Debe quedar así (los `db_*` normalmente ya vienen; no los cambies):

```ini
[options]
admin_passwd = PON_AQUI_TU_CONTRASEÑA_MAESTRA
db_host = False
db_port = False
db_user = odoo
db_password = False
http_port = 8069
log_level = info
```

`db_host = False` significa "servidor local, por socket" → usa el PostgreSQL de la misma máquina.

```bash
sudo systemctl restart odoo
```

```bash
sudo ss -tlnp | grep -E "8069|5432"
```

📸 Odoo en `0.0.0.0:8069`; PostgreSQL en `127.0.0.1:5432` (y `::1`), **no** en `0.0.0.0`. Eso confirma que PostgreSQL solo es accesible desde Ubuntu. Compruébalo también:

```bash
sudo -u postgres psql -c "SHOW listen_addresses;"
```

### Regla NAT Odoo-directo

| Nombre | Puerto anfitrión | Puerto invitado |
|---|---|---|
| Odoo-directo | 18069 | 8069 |

### UFW (reglas ANTES de activar)

```bash
sudo ufw allow 22/tcp
```

```bash
sudo ufw allow 8069/tcp
```

```bash
sudo ufw enable
```

```bash
sudo ufw status verbose
```

No se abre el 5432: PostgreSQL ya solo escucha en local y además el firewall lo bloquea (doble protección). 📸

### Crear la base de datos

En Windows abre `http://localhost:18069`:

- Master Password: tu contraseña maestra
- Database Name: `ua2_ubuntu`
- Email: `alumno@ua2.local`
- Password: (la que quieras, apúntala)
- Language: Español (ES) / Country: España
- **Demo data: desmarcado**

📸 Formulario relleno, y luego pantalla tras iniciar sesión.

### Para el informe – Contraseña maestra vs. contraseña del administrador

- La **contraseña maestra** (`admin_passwd` en `odoo.conf`) protege el **gestor de bases de datos** de Odoo (`/web/database/manager`): crear, duplicar, hacer copias, restaurar y **borrar** bases de datos. Es del servidor Odoo, afecta a todas las bases de datos y no sirve para iniciar sesión.
- La **contraseña de la cuenta administradora** (`alumno@ua2.local`) sirve para **iniciar sesión dentro de una base de datos concreta** (`ua2_ubuntu`) y gestionar sus datos, usuarios y aplicaciones. Se guarda (cifrada) en la tabla `res_users` de esa base de datos.

Resumen: la maestra manda sobre las bases de datos como "archivos"; la del administrador manda sobre lo que hay dentro de una de ellas.

---

## 4. Instalar Sitio web (`website`) desde la terminal

Se para el servicio para que no haya dos Odoo usando la base de datos a la vez:

```bash
sudo systemctl stop odoo
```

```bash
sudo -u odoo odoo -c /etc/odoo/odoo.conf -d ua2_ubuntu -i website --stop-after-init --logfile=
```

(`--logfile=` vacío hace que el log salga por pantalla y puedas capturar el proceso.)

```bash
sudo systemctl start odoo
```

Comprobar estado y dependencias:

```bash
sudo -u postgres psql -d ua2_ubuntu -c "SELECT name, state, latest_version FROM ir_module_module WHERE name='website';"
```

```bash
sudo -u postgres psql -d ua2_ubuntu -c "SELECT d.name AS depende_de, m.state FROM ir_module_module_dependency d JOIN ir_module_module m ON m.name=d.name WHERE d.module_id=(SELECT id FROM ir_module_module WHERE name='website') ORDER BY 1;"
```

📸 `website | installed` y la lista de dependencias (todas `installed`, Odoo las instala automáticamente).

En el navegador: abre la app **Sitio web** y **Sitio web → Configuración → Ajustes**. 📸 No crees páginas.

---

## 5. Archivos de la instalación

```bash
dpkg -L odoo | grep -vE "\.py$|\.pyc$|/static/|/i18n/" | head -40
```

```bash
systemctl cat odoo
```

```bash
sudo cat /etc/odoo/odoo.conf
```

Valores efectivos de Odoo (abre una consola de Odoo):

```bash
sudo -u odoo odoo shell -c /etc/odoo/odoo.conf -d ua2_ubuntu --no-http --logfile=
```

Dentro:

```python
from odoo.tools import config
print(config['addons_path']); print(config['data_dir']); print(config['db_host'], config['db_port'])
exit()
```

Conexiones activas de Odoo en PostgreSQL:

```bash
sudo -u postgres psql -c "SELECT usename, datname, client_addr, client_port FROM pg_stat_activity WHERE usename='odoo';"
```

PostgreSQL:

```bash
sudo -u postgres psql -c "SHOW config_file;" -c "SHOW data_directory;" -c "SHOW port;" -c "SHOW listen_addresses;" -c "SHOW unix_socket_directories;" -c "SHOW hba_file;"
```

### Para el informe – Respuestas

**a) db_host, db_port, db_user, db_password. ¿Socket o TCP?**
En `/etc/odoo/odoo.conf`: `db_host = False`, `db_port = False`, `db_user = odoo`, `db_password = False` (no hay contraseña; si la tuvieras, no la copies). Al no indicar host, la librería de conexión (psycopg2) no usa TCP sino el **socket local de Unix** en `/var/run/postgresql` (lo confirma `SHOW unix_socket_directories`). Lo he comprobado con `pg_stat_activity`: las conexiones del usuario `odoo` tienen `client_addr` **vacío**, que es lo que aparece en las conexiones por socket (por TCP aparecería `127.0.0.1`). Como no hay contraseña, PostgreSQL autentica por *peer*: comprueba que el usuario del sistema (`odoo`) coincide con el rol de la base de datos (regla `local all all peer` en `pg_hba.conf`).

**b) addons_path y data_dir**
- `addons_path`: carpetas donde Odoo busca módulos (aplicaciones). En la instalación por paquete: `/usr/lib/python3/dist-packages/odoo/addons` (comprueba la ruta exacta en tu salida).
- `data_dir`: carpeta donde Odoo guarda datos que no van a la base de datos (filestore, sesiones). No aparece en `odoo.conf`, así que se usa el valor por defecto `~/.local/share/Odoo` del usuario `odoo`, cuyo home es `/var/lib/odoo` → **`/var/lib/odoo/.local/share/Odoo`**.

**c) Filestore de ua2_ubuntu**

```bash
sudo ls -la /var/lib/odoo/.local/share/Odoo/filestore/ua2_ubuntu | head
```

```bash
sudo du -sh /var/lib/odoo/.local/share/Odoo/filestore/ua2_ubuntu
```

```bash
sudo -u postgres psql -d ua2_ubuntu -c "SELECT id, name, mimetype, store_fname FROM ir_attachment WHERE store_fname IS NOT NULL LIMIT 5;"
```

Está en `/var/lib/odoo/.local/share/Odoo/filestore/ua2_ubuntu`. Guarda los **archivos binarios** (adjuntos, imágenes, logos, CSS/JS compilados de la web…). Tiene subcarpetas de 2 caracteres (`3a/`, `f1/`…) y dentro archivos cuyo nombre es su **huella SHA-1**. La base de datos no guarda el archivo, solo una ficha en la tabla `ir_attachment` cuyo campo `store_fname` (p. ej. `3a/3a9f…`) apunta al archivo. Por eso una copia de seguridad necesita **las dos partes**: base de datos + filestore. Si falta una, se pierden imágenes y adjuntos.

**d) Logs de Odoo**
En `/var/log/odoo/odoo-server.log` (lo fija `--logfile` en `ExecStart` de `systemctl cat odoo`), con nivel `info` (`log_level = info`).

```bash
sudo tail -n 15 /var/log/odoo/odoo-server.log
```

Ejemplo de interpretación (usa una línea tuya):
`2026-11-24 10:15:03,421 1234 INFO ua2_ubuntu werkzeug: 10.0.2.2 - - [24/Nov/2026 10:15:03] "POST /web/login HTTP/1.1" 303 - 31 0.020 0.110`
→ **Fecha/hora** `2026-11-24 10:15:03,421` (en UTC) · **PID** 1234 · **Nivel** `INFO` · **BD** `ua2_ubuntu` · **origen** `werkzeug` (servidor web interno) · **Mensaje**: petición `POST /web/login` desde `10.0.2.2` (el NAT de VirtualBox, o sea, Windows) con respuesta `303` (redirección tras un inicio de sesión correcto).

**e) website/__manifest__.py**

```bash
sudo cat /usr/lib/python3/dist-packages/odoo/addons/website/__manifest__.py | head -40
```

Anota los valores reales. Normalmente: `name: 'Website'`, `version` tipo `'1.0'`, `depends` con módulos como `web`, `http_routing`, `portal`, `mail`, `auth_signup`, `social_media`, `utm`, `digest`… Los dos primeros de `data` suelen ser de **seguridad** (`security/website_security.xml` y `security/ir.model.access.csv`): Odoo los carga primero para crear los grupos/reglas y los **permisos de acceso a los modelos** antes de crear vistas, menús y datos que dependen de ellos.

---

## 6. Nginx y HTTPS

### Fase HTTP

```bash
sudo apt install -y nginx
```

```bash
sudo systemctl enable --now nginx
```

En `odoo.conf` añade:

```ini
proxy_mode = True
```

```bash
sudo systemctl restart odoo
```

Crea el sitio a partir de la plantilla `odoo_ua2` del profesor. Una versión completa está en `config/odoo-ua2.nginx.conf` de este repositorio. En la **primera fase** usa un único `server { listen 80; ... }` con las `location` del bloque 443 (sin `ssl_*` ni `return 301`).

```bash
sudo nano /etc/nginx/sites-available/odoo-ua2
```

```bash
sudo ln -s /etc/nginx/sites-available/odoo-ua2 /etc/nginx/sites-enabled/odoo-ua2
```

```bash
sudo rm /etc/nginx/sites-enabled/default
```

```bash
sudo nginx -t
```

```bash
sudo systemctl reload nginx
```

```bash
sudo ufw allow 80/tcp
```

Regla NAT **Nginx-HTTP**: 18080 → 80. Abre `http://localhost:18080`, inicia sesión y navega: la URL debe seguir con `:18080`. 📸

### Para el informe – Escucha, destino y cabeceras

- **Escucha**: `listen 80;` / `listen 443 ssl;` con `server_name localhost;`.
- **Destino**: `proxy_pass http://127.0.0.1:8069;` (vía `upstream`).
- **Cabeceras**: `Host $http_host` y `X-Forwarded-Host $http_host` (nombre **y puerto** que escribió el navegador, p. ej. `localhost:18080`), `X-Forwarded-Proto $scheme` (http o https), `X-Forwarded-For` / `X-Real-IP` (IP real del cliente). Con `proxy_mode = True` Odoo confía en estas cabeceras para construir sus URLs y redirecciones. Si se usara `$host` en vez de `$http_host`, se perdería el puerto 18080 y Odoo redirigiría a `http://localhost/…`, que en Windows no existe.

### Certificado autofirmado

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 -days 30 -keyout /etc/ssl/private/odoo-ua2.key -out /etc/ssl/certs/odoo-ua2.crt -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

```bash
sudo chmod 600 /etc/ssl/private/odoo-ua2.key
```

```bash
openssl x509 -in /etc/ssl/certs/odoo-ua2.crt -noout -subject -issuer -dates -ext subjectAltName
```

### Fase HTTPS

Sustituye el sitio por la versión completa de `config/odoo-ua2.nginx.conf`.

```bash
sudo nginx -t && sudo systemctl reload nginx
```

```bash
sudo ufw allow 443/tcp
```

```bash
sudo ufw status numbered
```

Regla NAT **Nginx-HTTPS**: 18443 → 443.

Pruebas:
- `https://localhost:18443` → aviso de seguridad → Avanzado → Continuar. Inicia sesión y navega. 📸
- `http://localhost:18080/odoo/contacts` → debe acabar en `https://localhost:18443/odoo/contacts` (misma ruta). 📸
- Candado/aviso → Ver certificado: CN `localhost`, emisor `localhost` (el mismo, por ser autofirmado), validez 30 días, SAN `DNS:localhost, IP:127.0.0.1`. 📸

### Para el informe – Aviso del certificado autofirmado

El navegador solo confía en certificados firmados por una **autoridad de certificación (CA)** que tiene en su lista de confianza. Un certificado autofirmado está firmado por sí mismo (emisor = sujeto), así que el navegador no puede comprobar que quien lo presenta es quien dice ser y muestra el aviso (`NET::ERR_CERT_AUTHORITY_INVALID`). **El cifrado funciona igual**: los datos viajan cifrados; lo que falta es la garantía de identidad. En un entorno de prácticas es aceptable; en producción se usaría una CA (p. ej. Let's Encrypt).

### Estado y logs de Nginx

```bash
systemctl status nginx --no-pager
```

```bash
sudo tail -n 20 /var/log/nginx/odoo-ua2.access.log
```

```bash
sudo tail -n 20 /var/log/nginx/odoo-ua2.error.log
```

Ejemplo de interpretación:
`10.0.2.2 - - [24/Nov/2026:11:02:10 +0100] "GET /odoo/contacts HTTP/1.1" 200 5231 "-" "Mozilla/5.0 (Windows NT 10.0; ...)"`
→ cliente `10.0.2.2` (Windows a través del NAT de VirtualBox), fecha, método `GET`, ruta `/odoo/contacts`, código `200` (correcto), tamaño 5231 bytes, navegador de Windows. Busca también un `301` en el puerto 80 (la redirección a HTTPS).

### Cerrar el acceso directo a Odoo

En `odoo.conf`:

```ini
http_interface = 127.0.0.1
```

```bash
sudo systemctl restart odoo
```

```bash
sudo ss -tlnp | grep 8069
```

(Ahora debe verse `127.0.0.1:8069`, no `0.0.0.0:8069`.)

```bash
sudo ufw delete allow 8069/tcp
```

```bash
sudo ufw status
```

Borra la regla NAT **Odoo-directo** en VirtualBox. Quedan SSH, Nginx-HTTP y Nginx-HTTPS. 📸
Prueba: `http://localhost:18069` → no conecta 📸; `https://localhost:18443` → funciona 📸.

### Para el informe – Recorrido de la petición

```
 Windows                       VirtualBox NAT           Ubuntu (10.0.2.15)
┌──────────────┐  HTTPS   ┌──────────────────┐  HTTPS  ┌─────────────┐  HTTP          ┌───────────┐  socket Unix      ┌──────────────┐
│ Navegador    │─────────►│ 127.0.0.1:18443  │────────►│ Nginx :443  │──────────────►│ Odoo      │─────────────────►│ PostgreSQL   │
│ localhost:   │          │   → 10.0.2.15:443│         │ (UFW 443 ✔) │ 127.0.0.1:8069 │ (solo     │ /var/run/        │ 16 :5432     │
│ 18443        │          │                  │         │ termina TLS │                │ localhost)│ postgresql       │ (solo local) │
└──────────────┘          └──────────────────┘         └─────────────┘                └───────────┘                  └──────────────┘
 ◄══════════════ TLS (cifrado) ═══════════════════════►│◄────────────── sin cifrar, pero sin salir de Ubuntu ──────────────────►

 http://localhost:18080 → NAT → Nginx :80 → 301 a https://localhost:18443/<misma ruta>
 http://localhost:18069 → ya no hay regla NAT, Odoo solo escucha en 127.0.0.1 y UFW no permite 8069 → no conecta
```

TLS protege el tramo **navegador ↔ Nginx** (incluido el paso por el NAT). De Nginx a Odoo y de Odoo a PostgreSQL el tráfico no está cifrado, pero nunca sale de la propia VM.

---

## 7. Persistencia y diagnóstico de una parada

1. **Contactos → Nuevo**: `Prueba P2 - Ubuntu`, correo `prueba.p2@example.com` → Guardar. 📸 (Si no aparece Contactos, instálala desde Aplicaciones.)
2. Reiniciar:

```bash
sudo reboot
```

3. Tras el reinicio, desde Windows:

```bash
ssh -p 2222 TU_USUARIO@127.0.0.1
```

```bash
systemctl is-active ssh nginx odoo postgresql
```

```bash
sudo ufw status
```

```bash
sudo -u postgres psql -d ua2_ubuntu -c "SELECT name, state FROM ir_module_module WHERE name='website';"
```

Abre `https://localhost:18443`, busca el contacto y comprueba nombre y correo. 📸

4. Parar solo Odoo:

```bash
sudo systemctl stop odoo
```

En el navegador → **502 Bad Gateway** (página de Nginx). 📸

```bash
systemctl is-active nginx odoo postgresql
```

(`active`, `inactive`, `active`.)

```bash
sudo tail -n 15 /var/log/odoo/odoo-server.log
```

```bash
sudo tail -n 5 /var/log/nginx/odoo-ua2.error.log
```

Esperado en Nginx: `connect() failed (111: Connection refused) while connecting to upstream, ... upstream: "http://127.0.0.1:8069/..."`.
En Odoo: las últimas líneas de la parada (`Initiating shutdown` / `Hit CTRL-C again or send a second signal to force the shutdown`).

**Diagnóstico para el informe**: Nginx sigue funcionando y acepta la conexión HTTPS, pero al reenviarla a `127.0.0.1:8069` no hay nadie escuchando (conexión rechazada), así que devuelve 502. PostgreSQL está bien. El fallo está en Odoo.

```bash
sudo systemctl start odoo && systemctl is-active odoo
```

📸 Odoo vuelve a funcionar.

---

## 8. Comparativa nativa vs. Docker

> Ajusta la columna Docker con los **nombres reales de tu Actividad 1** (nombre del contenedor, volúmenes y ruta del `docker-compose.yml`). Consúltalos con `docker compose ps` y `docker volume ls`.

| Aspecto | Instalación nativa (esta práctica) | Docker (Actividad 1) |
|---|---|---|
| **Inicio, parada, reinicio y estado** | `sudo systemctl start/stop/restart odoo` · `systemctl status odoo` · arranque automático con `systemctl enable odoo` · logs en `/var/log/odoo/odoo-server.log` | `docker compose up -d` / `docker compose stop` / `docker compose restart odoo` · `docker compose ps` · logs con `docker compose logs -f odoo` · arranque automático con `restart: unless-stopped` |
| *Diferencia* | Odoo es un servicio más del sistema, gestionado por systemd. | Odoo y PostgreSQL son contenedores gestionados por Docker; se manejan juntos desde la carpeta del `docker-compose.yml`. |
| **Configuración y aplicación de cambios** | `/etc/odoo/odoo.conf` (copia en `odoo.conf.p2.bak`). Se edita con `nano` y se aplica con `sudo systemctl restart odoo`. La conexión a BD va en el propio `odoo.conf`. | `docker-compose.yml` (variables `HOST`, `USER`, `PASSWORD`, puertos) + `./config/odoo.conf` montado en `/etc/odoo/odoo.conf` dentro del contenedor. Se aplica con `docker compose restart odoo` (o `docker compose up -d` si cambia el compose). |
| *Diferencia* | Un solo archivo en el sistema. | La configuración se reparte entre el compose y el `odoo.conf` montado; cambiar el compose recrea el contenedor. |
| **Base de datos y filestore** | PostgreSQL 16 nativo: datos en `/var/lib/postgresql/16/main` (`SHOW data_directory`). Filestore en `/var/lib/odoo/.local/share/Odoo/filestore/ua2_ubuntu`. | Datos de PostgreSQL en un volumen (p. ej. `odoo-db-data` → `/var/lib/postgresql/data`). Filestore en otro volumen (p. ej. `odoo-web-data` → `/var/lib/odoo/filestore/<bd>`). Se ven con `docker volume inspect`. |
| *Diferencia* | Los datos están en carpetas normales del disco de Ubuntu. | Los datos viven en volúmenes de Docker: sobreviven aunque borres el contenedor, pero se pierden con `docker compose down -v`. |

---

## Checklist de capturas

- [ ] 1 – Adaptador NAT y reglas de reenvío
- [ ] 1 – `ip -br a`, `ip route`, pings
- [ ] 1 – OpenSSH activo y conexión desde Windows por 2222
- [ ] 1 – `~/ua2_p2`, `terminal.txt` y `terminal_copia.txt`
- [ ] 2 – Versiones, `pg_lsclusters`, puerto 5432, servicios activos y habilitados, logs
- [ ] 3 – Copia `.p2.bak`, `odoo.conf` editado (tapa la contraseña), `ss`, UFW
- [ ] 3 – Creación de `ua2_ubuntu` e inicio de sesión
- [ ] 4 – Instalación de `website` por terminal, estado y dependencias, app y ajustes
- [ ] 5 – `dpkg -L`, `systemctl cat`, config efectiva, filestore, log, manifest, `SHOW`
- [ ] 6 – `nginx -t`, acceso por 18080, certificado, HTTPS 18443, redirección, logs
- [ ] 6 – 18069 sin acceso, 18443 funcionando, reglas finales NAT y UFW
- [ ] 7 – Contacto, comprobaciones tras reinicio, 502, logs y recuperación
- [ ] 8 – Tabla comparativa con datos reales
