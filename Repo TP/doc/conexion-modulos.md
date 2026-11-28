# Diseño de conexión y mensajería — TP EntrenadOS (SO 2C2026)

> Alcance: todo lo exigido por el **Check 1 (12/09) — Conexiones y
> Serialización** y la base de comunicación para el resto del TP.
> Fuente: enunciado v1.0 archivado en la bóveda. Las decisiones de
> protocolo (opcodes, framing) son propuestas del equipo: el enunciado
> las deja a criterio del grupo y se justifican en el coloquio.
> Responsable sugerido: D5 (protocolo/serialización), con D1–D4
> implementando la punta de su módulo.

## 1. Qué pide el Check 1 exactamente

- Arquitectura de red y ruteo de mensajes básica.
- Planificador, Placa y Storage inicializan sus **servidores multihilo**.
- El Core se conecta con éxito a **Planificador y Placa**, realiza un
  **handshake inicial para identificarse** y envía/recibe un **paquete de
  mensajes serializado** como prueba.
- Test: se levantan los **4 procesos de forma aislada** y se valida por
  logs obligatorios que los handshakes se hacen bien y que los paquetes
  viajan sin cuelgues ni caídas de conexión.

## 2. Matriz de conexiones

| # | Origen → Destino | Rol origen | Cuándo | Qué viaja después (TP completo) |
|---|---|---|---|---|
| 1 | Planificador → Placa | cliente | al iniciar | crear Job, ALLOC/FREE, carga de página (page fault), lectura/escritura, deslockeo, finalización de Job |
| 2 | Planificador → Storage | cliente | al iniciar | guardar / cargar / eliminar Checkpoint |
| 3 | Core → Planificador | cliente | al iniciar | recibir JID + contexto de ejecución, devolver contexto (syscall/ page fault/ EXIT), solicitar syscalls, recibir interrupciones |
| 4 | Core → Placa | cliente | al iniciar | Fetch de instrucción por PC, obtención de marco (MMU), lectura/escritura de memoria |

Servidores a la escucha (todos multihilo, `PUERTO_ESCUCHA` en config):

| Servidor | Acepta conexiones de | Particularidad |
|---|---|---|
| Planificador | Cores (1..N) | los Cores se conectan y **desconectan en runtime**; la escucha queda siempre activa |
| Placa | Planificador + Cores (1..N) | concurrencia entre todos ellos |
| Storage | Planificador | un único tipo de cliente |

**Orden de arranque** (las flechas del enunciado son dependencias):

```
   Placa      Storage        (independientes entre sí, primero)
      ▲           ▲
      └── Planificador ──┘   (se conecta a ambos y recién después abre su servidor)
              ▲
              └── Core(s)    (necesita Planificador y Placa ya iniciados)
```

Si el Planificador no logra conectarse a Placa/Storage al arrancar, debe
loguear el error y abortar: después de ese punto ya queda sirviendo Cores.

## 3. Handshake (identificación)

Primer mensaje de toda conexión, en ambos sentidos de información:

```c
// Emisor (el que se conecta)
typedef enum {
    MODULO_PLANIFICADOR, MODULO_CORE, MODULO_PLACA, MODULO_STORAGE
} t_modulo;

typedef struct {
    t_modulo modulo;        // quién soy
    uint32_t id_core;       // solo si modulo == CORE: identificador por parámetro
} handshake_msg;
```

Secuencia propuesta:

1. Cliente conecta (`connect`) y manda `OP_HANDSHAKE` + su `t_modulo`
   (+ `id_core` si corresponde).
2. Servidor responde `OP_HANDSHAKE_OK` (o `OP_HANDSHAKE_ERROR` y cierra).
3. Servidor loguea la conexión recibida; cliente loguea la establecida.

Con esto Placa distingue un Core de un Planificador, y Planificador
registra cada Core por ID (desconexión de Core en el TP final: el Job
vuelve a READY y se deslockean páginas — conviene keyed by `id_core`).

## 4. Framing del protocolo

Formato único de paquete (propuesta):

```
+---------+------------------+---------------------+
| opcode  | payload_size     | payload             |
| 1 byte  | uint32_t (4, LE) | payload_size bytes  |
+---------+------------------+---------------------+
```

- **Little-endian** en todo multibyte (x86/ARM del aula lo son).
- `payload_size` permite `recv` exacto y detección de corrupción.
- Todo `recv`/`send` debe ser **ciego al tamaño del buffer del SO**:
  implementar `recv_all(fd, buf, n)` que itere hasta completar `n` bytes.
  Es la causa n.º 1 de "funciona a veces" en estos TPs.

Tabla general de opcodes (borrador, se completa por etapa):

| Flujo | Opcode | Payload (resumen) |
|---|---|---|
| Handshake | `OP_HANDSHAKE` / `_OK` / `_ERROR` | `t_modulo` + `id_core?` |
| Core→Placa | `OP_FETCH_INSTRUCCION` | JID, PC → instrucción (texto) |
| Core→Placa | `OP_OBTENER_MARCO` | JID, nro_página → marco o PAGE_FAULT |
| Core↔Placa | `OP_READ_MEM` / `OP_WRITE_MEM` | dir. física, tamaño, contenido |
| Planificador↔Placa | `OP_CREATE_JOB` / `OP_ALLOC` / `OP_FREE` / `OP_LOAD_PAGE` / `OP_UNLOCK_PAGES` / `OP_END_JOB` | ver operaciones de la Placa |
| Planificador↔Storage | `OP_SAVE_CKPT` / `OP_LOAD_CKPT` / `OP_DELETE_CKPT` | nombre, tamaño, contenido |
| Core↔Planificador | `OP_DISPATCH` (JID+contexto) / `OP_SYSCALL` / `OP_INTERRUPTION` | opcode de syscall + parámetros |

Regla de oro Check 2+: las interrupciones del Planificador al Core no se
envían por la misma cola de solicitudes — si el Core está bloqueado
esperando respuesta, planear un hilo de "receive" separado o un canal de
señalización (diseño a decidir y defender en coloquio).

## 5. Serialización

- Buffers dinámicos (`void*` + tamaño) construidos con helpers
  `serializar_uint32 / serializar_string / serializar_bytes`.
- Strings: `uint32_t largo` + bytes (sin '\0' o con él, pero decidirlo
  una vez y documentarlo).
- El contexto de ejecución (16 registros uint32_t = 64 bytes) viaja
  empaquetado y alineado: definir un solo `pack/unpack` compartido.
- Código de protocolo **en una biblioteca común del repo** que todos los
  módulos linkean: una sola implementación de `recv_all`, framing y
  serialización. Evita cinco versiones divergentes.

## 6. Concurrencia de los servidores

- Patrón: hilo aceptador (`accept` en loop infinito) + **un hilo por
  conexión** (dispatch a handler según el módulo del handshake).
- El Planificador debe soportar `N` Cores simultáneos y la salida limpia
  de cualquiera (el socket da EOF / `recv == 0`: cerrar, cancelar hilo,
  y en etapas posteriores recuperar el Job que ejecutaba).
- Conexiones Planificador→Placa y Planificador→Storage son persistentes
  y únicas: crearlas al inicio y reutilizarlas.

## 7. Config y logs obligatorios por módulo (Check 1)

Config mínima (enunciado):

| Módulo | Campos |
|---|---|
| Planificador | `PUERTO_ESCUCHA`, `IP_PLACA`, `PUERTO_PLACA`, `IP_STORAGE`, `PUERTO_STORAGE`, `LOG_LEVEL` |
| Core | `IP_PLANIFICADOR`, `PUERTO_PLANIFICADOR`, `IP_PLACA`, `PUERTO_PLACA`, `LOG_LEVEL` |
| Placa | `PUERTO_ESCUCHA`, `LOG_LEVEL` |
| Storage | `PUERTO_ESCUCHA`, `LOG_LEVEL` |

Logs obligatorios (formato exacto, so-commons `LOG_LEVEL_INFO`, a
archivo — sin esto el TP no es evaluable):

- Planificador / Placa / Storage — conexión recibida:
  `## Módulo: <NOMBRE_MODULO_CONECTADO>`
- Core — conexión establecida:
  `## Conectado a <Planificador/Placa> exitosamente`

## 8. Ensayo del Check 1 (procedimiento de prueba)

1. Levantar los 4 procesos **en terminales/VMs separadas** con las IPs
   reales de la prueba (no siempre localhost).
2. Verificar en cada log el handshake en ambos extremos.
3. Programa de smoke test (temporizado): el Core envía un paquete
   serializado al Planificador, este lo reenvía a la Placa, la Placa
   responde, y el Core imprime el eco. Sin cuelgues ni desconexiones.
4. Matar un Core (Ctrl+C) y verificar que Planificador y Placa loguean
   la desconexión y siguen vivos.
5. Correr el smoke test con `valgrind` (sin leaks ni errores de socket).

## 9. Errores comunes a evitar

- `recv` único asumiendo que llega todo el mensaje (TCP fragmenta).
- Mezclar endianness o tamaños de tipos entre módulos (`uint32_t`
  explícito siempre; nada de `int` directo por el wire).
- Hilos detached sin limpieza de recursos al desconectar un Core.
- Bloquear el hilo de accept con handlers monolíticos: el servidor deja
  de aceptar Cores nuevos (el enunciado exige escucha siempre activa).
- Logs por pantalla en vez de archivo (TP no apto).

## 10. Referencias

- Enunciado: bóveda, página canónica `wiki/sources/tp-so-2c2026-entrenados.md`.
- Tablero de tareas: `EntrenadOS - Tablero Trello.json` (columna Check 1).
- Distribución de responsables: `distribucion-equipo.md` (este directorio).
- so-commons-library: https://sisoputnfrba.github.io/so-commons-library/
- Foro de consultas (decisiones de diseño): https://github.com/sisoputnfrba/foro
