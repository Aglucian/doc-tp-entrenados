# Biblioteca compartida `utils` — TP EntrenadOS (SO 2C2026)

> Notas de diseño de la biblioteca que linkean los cuatro módulos.
> El código de `utils/src/utils/` va con comentarios mínimos: el fundamento
> de cada decisión está acá.
> Ver también: `conexion-modulos.md` (matriz de conexiones y handshake) y
> `planificador.md` (uso desde el Planificador).

## 1. Por qué existe

En el TP anterior (RequiemSO) cada módulo terminó con su propia versión del
protocolo y de la serialización. La duplicación derivó en tres conexiones
rotas y en structs que divergían entre `cpu/` y `kernel_scheduler/`. En
EntrenadOS hay una sola implementación de sockets, framing y serialización,
y los cuatro módulos la consumen sin reescribirla.

Consecuencia práctica: si a un módulo le falta un mensaje o un helper, se
agrega en `utils` y se avisa al equipo. No se define un opcode propio dentro
de un módulo.

## 2. `protocolo_entrenados.h` — la única fuente de verdad

Concentra opcodes, `t_modulo`, `handshake_msg`, `t_contexto` y los ids de
syscalls. Si dos módulos discrepan sobre un mensaje, este header manda.

Los opcodes están agrupados en rangos por flujo para que agregar mensajes no
obligue a renumerar:

| Rango | Flujo |
|---|---|
| `0x00`–`0x0F` | handshake y control |
| `0x10`–`0x2F` | Planificador → Placa |
| `0x30`–`0x3F` | Planificador → Storage |
| `0x40`–`0x5F` | Planificador ↔ Core |
| `0x60`–`0x6F` | Core → Placa |

Nota: `planificador.md` §2.6 propone rangos de dos bytes (`0x01xx`). Con el
framing de 1 byte de opcode que fija `conexion-modulos.md` §4 no entran, y
255 opcodes sobran para el TP. Si alguna vez hicieran falta más, hay que
cambiar el framing y los cuatro módulos a la vez.

## 3. Framing

```
+----------+------------------+---------------------+
| opcode   | payload_size     | payload             |
| 1 byte   | uint32_t (4, LE) | payload_size bytes  |
+----------+------------------+---------------------+
```

Todo lo multibyte viaja en little-endian explícito (`htole32`/`le32toh`), no
en el orden nativo. Los strings viajan como `uint32_t` largo + los bytes,
**incluyendo el `'\0'`**.

Tres decisiones que no son obvias leyendo el código:

- **`enviar_todo`/`recibir_todo` iteran hasta completar los N bytes.** TCP
  fragmenta: un `recv` único asumiendo que llegó el mensaje entero es la
  causa número uno de los "funciona a veces" de este TP.
- **`enviar_paquete` arma header y payload en un solo `send`.** Con tres
  `send` consecutivos, dos hilos escribiendo sobre el mismo socket
  intercalan sus mensajes y el receptor lee basura. Importa desde la Fase 2,
  donde el despacho a un Core y su `timer_quantum` comparten socket.
- **`recibir_paquete` corta si el tamaño supera `MAX_PAYLOAD_SIZE`.** Un
  payload mayor a 16 MB es corrupción de stream, y sin la cota se traduce en
  un `malloc` gigante ante cualquier basura en el socket.

## 4. Serialización

`t_buffer` es un buffer dinámico que se arma en el emisor y se lee en el
receptor.

```c
// emisor
t_buffer* b = buffer_crear();
buffer_agregar_uint32(b, jid);
buffer_agregar_string(b, path);
enviar_buffer(socket, OP_CREAR_JOB, b);   // destruye b

// receptor, con el payload ya recibido
t_buffer* b = buffer_desde_payload(payload, payload_size);
uint32_t jid = buffer_leer_uint32(b);
char* path   = buffer_leer_string(b);     // free() del caller
buffer_destruir(b);
```

**Las lecturas nunca se pasan del final del stream.** Si el payload viene
corto devuelven `0`/`NULL` y dejan el buffer marcado como inválido. El
handler tiene que chequear `buffer_es_valido()` antes de usar los datos: sin
eso, un paquete malformado se convierte en un segfault en vez de en un log
de error.

## 5. `conexiones` y `herramientas`

`conexiones` cubre las dos puntas: `crear_servidor`/`esperar_cliente` del
lado servidor y `crear_conexion` del lado cliente, más el handshake en sus
dos formas (`handshake_cliente` hace el paso completo; `enviar_handshake`,
`recibir_handshake` y `responder_handshake` quedan sueltas por si un módulo
necesita intercalar lógica).

`herramientas` centraliza el arranque. `iniciar_logger` siempre escribe a
archivo porque las Normas del TP exigen los logs mínimos en `LOG_LEVEL_INFO`
a archivo, y sin eso el TP no es evaluable. `config_tiene_claves` valida el
config completo al levantar el módulo: es preferible morir en el arranque
que a la mitad de una prueba del check.

## 6. Qué no hay que reimplementar

so-commons-library (v1.9.0) ya trae varias cosas que en RequiemSO se
escribieron a mano:

| Necesidad | Función de commons |
|---|---|
| Contenido en ASCII hexadecimal (Logger) | `mem_hexstring_plain()` — dos chars por byte, sin separadores |
| Archivo de reportes en modo append | `txt_open_for_append()` + `txt_write_in_file()` (hace `fflush`) |
| Cronómetro monotónico | `t_temporal` — usa `CLOCK_MONOTONIC_RAW`, devuelve milisegundos |

Dos advertencias sobre commons:

- **Las colecciones no tienen locking.** Ni `t_queue`, ni `t_list`, ni
  `t_dictionary`. Cada cola y cada lista compartida necesita su mutex.
- **El logger es seguro entre hilos, pero por la libc.** `commons/log.c` no
  tiene un solo mutex; lo que evita que las líneas se entremezclen es que
  arma la línea completa en un buffer y la escribe con un único `fprintf`,
  que glibc serializa por `FILE*`. Alcanza para loguear desde varios hilos,
  pero la garantía no viene de commons.
