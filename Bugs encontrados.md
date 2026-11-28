---
tags: [tp-so, entrenados, bugs]
actualizado: 2026-11-25
---

# Bugs encontrados y corregidos

Volver a [[00 - Inicio]] · Ver también [[Estado de ramas]], [[Protocolo]]

Registro de los bugs que aparecieron en cada rama del TP: qué fallaba, qué problema causaba y en qué commit se corrigió. Solo vive en este vault; el límite del livelock también está en [[limites-conocidos]] (`Repo TP/doc/`). Detalle de cada módulo en [[Planificador]], [[Core]], [[Placa]], [[Storage]] y [[Utils]].

- **Fecha**: la del commit que lo corrige.
- **Integración**: el PR con el que el arreglo llegó a `develop` (o a `main`, si se hizo directo en `develop`).
- Las fechas son de 2026.

## Resumen

| # | Rama | Bug | Corregido | Integración |
| --- | --- | --- | --- | --- |
| 1 | `utils` / `develop` | `op_code`, `t_modulo` y `t_buffer` definidos dos veces | `8ea0bc4`, `9e13a75`, `04e46a1` · 10/09 | #7 |
| 2 | `placa` | El servidor de la Placa no compilaba y no leía el payload | `8d2852e` · 09/09 | #5 |
| 3 | `core` | Inicialización por valor: el `main` usaba un `config` y un `logger` sin inicializar | `ea68438` · 07/10 | #10 |
| 4 | `core` | `SET`/`SUM`/`SUB` solo aceptaban números y siempre avanzaban el PC | `ea68438` · 07/10 | #10 |
| 5 | `core` | El Check Interrupt consumía solo el opcode de la interrupción | `ea68438` · 07/10 | #10 |
| 6 | `core` | Doble free al enviar mensajes y respuesta del FETCH mal leída | `15fae93`, `16722c2` · 08/10 | #10, #11 |
| 7 | `planificador` | Payloads incompatibles con el Core y la Placa | `a27dd3e` · 08/10 | #9 |
| 8 | `develop` | Opcode `OP_RSP_CREAR_JOB` duplicado con otro nombre | `08eb85d` · 08/10 | #11 |
| 9 | `develop` (storage) | El Storage no leía ni respondía el handshake | `80cdd9e` · 08/10 | #11 |
| 10 | `develop` (placa) | La Placa no aplicaba `RETARDO_MEMORIA` | `68a72fc` · 08/10 | #11 |
| 11 | `develop` (core) | Fuga de memoria en el nombre del log del Core | `06ea4fd` · 08/10 | #11 |
| 12 | `develop` (core) | Faltaba `INIT_JOB` y el log `Ejecutando:` cortaba parámetros | `16722c2` · 08/10 | #11 |
| 13 | `placa` | Funciones usadas sin declarar en `memoria.h` | `6a76f61` · 29/10 | #14 |
| 14 | `core` + `placa` | Los dos agregaban los mismos opcodes en `protocolo_entrenados.h` | merge · 30/10 | #12, #14 |
| 15 | `planificador` | Un Core que se caía dejaba páginas lockeadas para siempre | `169c8a8` · 30/10 | #15 |
| 16 | `core` | `ALLOC`/`FREE` no se ejecutaban y la interrupción guardada se borraba | `5ba1c3b` · 12/11 | #17 |
| 17 | `core` | `FREE` rechazado desconectaba al Core; `ALLOC` rechazado devolvía un Job ya finalizado | `69c087f` · 14/11 | #19 |
| 18 | `storage` | Ctrl-C cortaba el Storage con un error de `accept()` | `2a9b3b3` · 14/11 | #22 |
| 19 | `develop` (placa) | La Placa rechazaba el Job inicial con ruta absoluta | `896a387` · 14/11 | #23 |
| 20 | `develop` | Placa, Planificador y Core morían con Ctrl-C sin loguear el cierre | `9793672` · 24/11 | pendiente (`develop` → `main`) |
| 21 | `develop` (storage) | Los errores obligatorios del Storage no estaban en nivel INFO | `b93dfdd` · 24/11 | pendiente (`develop` → `main`) |
| 22 | `deploy` (planificador) | Dos Cores con el mismo ID se registraban a la vez | `d7dcf74` · 27/11 | pendiente (`deploy` → `develop`) |

---

## Check 1 (septiembre)

### 1. Definiciones duplicadas en utils
- **Rama:** `utils` y `develop` · corregido por Esteban Mengoni en `8ea0bc4`, `9e13a75` y `04e46a1` (10/09), integrado en #7.
- **Qué fallaba:**
  - `op_code`, `t_modulo` y `handshake_msg` estaban definidos en `conexiones.h` y también en el protocolo nuevo.
  - `serializacion.h` tenía el `t_buffer` repetido dos veces.
- **Problema:** cualquier módulo que incluyera los dos headers no compilaba (redefinición de tipos). Además, dos copias de la misma struct se pueden desincronizar, que fue justamente el problema del TP anterior.
- **Arreglo:** se dejó una sola definición; `protocolo_entrenados.h` quedó como única fuente de verdad.

### 2. Servidor de la Placa
- **Rama:** `placa` · `8d2852e` (Juana Fortuna, 09/09), integrado en #5.
- **Qué fallaba:**
  - `iniciar_servidor_placa()` estaba declarada como `int` pero hacía `return NULL` y `return;`.
  - El loop de atención leía solo el opcode (`recibir_codigo`) y dejaba el payload en el socket.
- **Problema:** no compilaba sin warnings. Además, cualquier paquete con payload desfasaba la lectura siguiente: el próximo "opcode" leído era en realidad un byte del payload anterior.
- **Arreglo:** la función pasó a `void` y se lee el paquete completo con `recibir_paquete()`.

## Check 2 (octubre)

### 3. Inicialización del Core por valor
- **Rama:** `core` · `ea68438` (scasasco, 07/10), integrado en #10.
- **Qué fallaba:**
  - `inicializar_core(t_config* config, t_log* logger, …)` recibía los punteros por valor: lo que creaba adentro no le llegaba al `main`.
  - `terminar_programa_core()` hacía `close()` de sockets que todavía valían `-1`.
- **Problema:** el `main` seguía con `config` y `logger` en `NULL`, así que el primer `log_info` o `config_get_*` rompía el Core al arrancar. Si fallaba una conexión, se cerraban descriptores inválidos.
- **Arreglo:** se pasan `t_config**` y `t_log**`, y solo se cierran los sockets abiertos.

### 4. `SET`, `SUM` y `SUB` del Core
- **Rama:** `core` · `ea68438` (07/10), integrado en #10.
- **Qué fallaba:**
  - `SET` hacía `atoi()` del operando, así que `SET AX BX` cargaba 0.
  - `SUM` exigía que el segundo operando fuera un registro.
  - Las tres avanzaban el PC aunque el destino fuera el propio `PC`.
- **Problema:** los scripts que usan registros como operando (los de la cátedra lo hacen) calculaban mal, y un salto con `SET PC …` quedaba corrido una instrucción.
- **Arreglo:** `obtener_valor_token()` acepta registro o número, y el `pc++` se omite cuando el destino es el `PC`.

### 5. Check Interrupt del Core
- **Rama:** `core` · `ea68438` (07/10), integrado en #10.
- **Qué fallaba:** el Core miraba el opcode con `MSG_PEEK` y, si era una interrupción, consumía **solo ese byte**. El payload (`jid`, `motivo`) quedaba en el socket, y no se verificaba que la interrupción fuera del Job actual.
- **Problema:** el mensaje siguiente del Planificador se leía desfasado. Una interrupción tardía de un Job anterior desalojaba al Job nuevo.
- **Arreglo:** se lee el mensaje completo y se descarta si el `jid` no es el que se está ejecutando.

### 6. Doble free y respuesta del FETCH
- **Rama:** `core` · `15fae93` (scasasco, 08/10) y `16722c2` (08/10), integrados en #10 y #11.
- **Qué fallaba:**
  - `enviar_buffer()` ya destruye el buffer, pero el Core lo volvía a destruir al enviar el FETCH y la devolución.
  - La respuesta del FETCH es `{bool ok, string instrucción}`, y el Core leía directamente el string.
- **Problema:** el doble free corrompía el heap: valgrind lo marcaba, y podía terminar en un crash aleatorio. Al leer mal la respuesta, la instrucción llegaba con basura al principio.
- **Arreglo:** se sacaron los `buffer_destruir()` sobrantes; ahora se lee el `ok` y después el string.

### 7. Payloads incompatibles entre el Planificador y el Core
- **Rama:** `planificador` · `a27dd3e` (Aglucian, 08/10), integrado en #9.
- **Qué fallaba:**
  - El Planificador mandaba la interrupción como `{motivo, jid}` y el Core la leía como `{jid, motivo}`.
  - Leía la devolución como `{uint32 motivo, uint32 jid, …}`, pero el Core la manda como `{uint32 jid, uint8 motivo, …}`.
  - No leía el `OP_RSP_CREAR_JOB {ok}` de la Placa.
- **Problema:**
  - Las interrupciones se descartaban siempre, porque el Core comparaba el motivo contra el JID: RR nunca desalojaba.
  - Las devoluciones se interpretaban con el motivo y el JID cruzados.
  - La respuesta de la Placa que no se leía quedaba en el socket y desfasaba el pedido siguiente (por ejemplo, el de finalización).
  - Además, se avisaba a la Placa la finalización de Jobs que nunca había creado.
- **Arreglo:** se unificó el orden con el del Core, se lee la confirmación de la creación y se agregó `creado_en_placa`.

### 8. Opcode duplicado con otro nombre
- **Rama:** `develop` · `08eb85d` (08/10), integrado en #11.
- **Qué fallaba:** para no chocar antes del merge, el Planificador había definido `OP_RSP_CREAR_JOB_PLACA (0x1F)` como copia local del opcode de la rama `placa`.
- **Problema:** dos nombres para el mismo valor: si uno cambiaba en el protocolo, el otro quedaba desfasado sin error de compilación.
- **Arreglo:** después del merge se usa `OP_RSP_CREAR_JOB` del protocolo.

### 9. Handshake del Storage
- **Rama:** `develop` (código del Storage) · `80cdd9e` (08/10), integrado en #11.
- **Qué fallaba:** el Storage no leía el handshake ni lo respondía: emitía `## Módulo: Planificador` fijo, sin saber quién se había conectado.
- **Problema:** el Planificador esperaba `OP_HANDSHAKE_OK` y fallaba al conectarse. Los bytes del handshake quedaban en el socket y se leían como si fueran el primer pedido. Además, cualquier módulo podía conectarse haciéndose pasar por el Planificador.
- **Arreglo:** `identificar_planificador()` valida el handshake, responde OK o ERROR y emite el log.

### 10. `RETARDO_MEMORIA` en la Placa
- **Rama:** `develop` (código de la Placa) · `68a72fc` (08/10), integrado en #11.
- **Qué fallaba:** la Placa leía `RETARDO_MEMORIA` del config pero no lo aplicaba.
- **Problema:** las pruebas que dependen del retardo (por ejemplo, las de RR con quantum) daban otros tiempos que los esperados.
- **Arreglo:** `aplicar_retardo_memoria()` antes de cada respuesta.

### 11. Fuga en el nombre del log del Core
- **Rama:** `develop` (código del Core) · `06ea4fd` (08/10), integrado en #11.
- **Qué fallaba:** el `string_from_format("core_%s.log", id)` no se liberaba.
- **Problema:** una fuga chica, pero valgrind la marca como *definitely lost* y la cátedra pide cero memory leaks.
- **Arreglo:** `free(nombre_log)` después de crear el logger.

### 12. `INIT_JOB` e interrupciones durante una syscall
- **Rama:** `develop` (código del Core) · `16722c2` (08/10), integrado en #11.
- **Qué fallaba:**
  - El Core no reconocía la instrucción `INIT_JOB`.
  - El log `Ejecutando:` mostraba como máximo dos parámetros.
- **Problema:** los scripts que crean Jobs terminaban con error, y el log obligatorio quedaba incompleto en instrucciones de 3 o 4 parámetros, como `FORWARD`.
- **Arreglo:**
  - se agregó `INST_INIT_JOB`, la primera syscall en la que el Core espera respuesta;
  - para que una interrupción de quantum que llega por el mismo socket no se tome como la respuesta, se guarda (`interrupcion_guardada`) y se atiende en el siguiente Check Interrupt (ver el #16);
  - el log imprime todos los parámetros.

## Check 3 (octubre y noviembre)

### 13. Declaraciones faltantes en la Placa
- **Rama:** `placa` · `6a76f61` (Juana Fortuna, 29/10), integrado en #14.
- **Qué fallaba:** `liberar_reserva()`, `seleccionar_victima()` y `pagina_del_marco()` se usaban sin estar declaradas en `memoria.h`.
- **Problema:** warnings de declaración implícita. Si el tipo de retorno no es `int` (`pagina_del_marco` devuelve un puntero), en 64 bits el valor se trunca y el resultado es un crash.
- **Arreglo:** se agregaron los prototipos.

### 14. Opcodes duplicados en el protocolo
- **Ramas:** `core` y `placa` · resuelto en los merges a `develop` (#12 y #14, 30/10).
- **Qué fallaba:** las dos ramas agregaban por separado `OP_TAM_PAGINA`, `OP_DESLOCKEAR_PAGINAS` y `OP_RSP_DESLOCKEAR_PAGINAS` en `protocolo_entrenados.h`.
- **Problema:** conflicto de merge. Peor aún, si se dejaban las dos copias, el mismo mensaje tendría dos valores distintos según el módulo.
- **Arreglo:** quedaron una sola vez, en `0x68`–`0x6A`.

### 15. Páginas lockeadas cuando se cae un Core
- **Rama:** `planificador` · `169c8a8` (Aglucian, 30/10), integrado en #15.
- **Qué fallaba:** si un Core se desconectaba mientras ejecutaba un Job, el Job volvía a READY, pero las páginas que el Core había lockeado en la Placa seguían lockeadas.
- **Problema:** esos marcos no podían ser víctima de reemplazo nunca más. Con pocos marcos, la Placa se quedaba sin víctimas y los page faults no se resolvían.
- **Arreglo:** al detectar la desconexión, `OP_DESLOCKEO_PAGINAS {jid}` antes de pasar el Job a READY.

### 16. `ALLOC` y `FREE` en el Core
- **Rama:** `core` · `5ba1c3b` (scasasco, 12/11), integrado en #17.
- **Qué fallaba:**
  - `INST_ALLOC` e `INST_FREE` no tenían implementación en `ejecutar_instruccion`.
  - En `syscalls.c`, cuando llegaba una interrupción mientras se esperaba la respuesta, se llamaba a `reiniciar_interrupcion_guardada()` en vez de `registrar_interrupcion_guardada()`.
- **Problema:** los Jobs con `ALLOC`/`FREE` terminaban por instrucción desconocida. La interrupción se borraba, así que con RR ese Job no se desalojaba al vencer el quantum.
- **Arreglo:** se implementaron las dos instrucciones y se cambió la llamada.

### 17. `ALLOC` y `FREE` rechazados
- **Rama:** `core` · `69c087f` (Aglucian, 14/11), integrado en #19.
- **Qué fallaba:**
  - Con `FREE` y `ok=false`, el Core hacía `goto error` y salía del ciclo de atención.
  - Con `ALLOC` y `ok=false`, el Core devolvía el Job con `EXIT`.
- **Problema:**
  - Un `FREE` de una dirección inválida **desconectaba al Core**: el Job volvía a READY y, si era el único Core, el sistema quedaba trabado.
  - En el caso de `ALLOC`, el Planificador ya había finalizado el Job (`OUT_OF_MEMORY`), así que recibía la devolución de un Job inexistente.
- **Arreglo:** `FREE` rechazado loguea un warning y el Job sigue; `ALLOC` rechazado devuelve `EJEC_JOB_FINALIZADO` y el Core abandona el Job sin devolverlo.

## Check 4 y entregas finales (noviembre)

### 18. Ctrl-C en el Storage
- **Rama:** `storage` · `2a9b3b3` (Aglucian, 14/11), integrado en #22.
- **Qué fallaba:** con Ctrl-C, readline (de la consola) atrapaba la señal y el `accept()` del servidor volvía con `EINTR`.
- **Problema:** un apagado normal quedaba logueado como `[ERROR] Falló accept(): Interrupted system call`, y el proceso moría sin cerrar el servidor ni loguear el cierre. Con el journaling (que llegó en `a2c6b63`, el mismo día) además hacía falta cerrar el volumen de forma ordenada.
- **Arreglo:**
  - `senales.c` maneja SIGINT/SIGTERM con un flag;
  - los hilos se crean con las señales bloqueadas, para que la señal le llegue al hilo del `accept()`;
  - `esperar_cliente()` ya no loguea `EINTR` como error.

### 19. Job inicial con ruta absoluta
- **Rama:** `develop` (código de la Placa) · `896a387` (14/11), integrado en #23.
- **Qué fallaba:** la Placa rechazaba los paths absolutos (`se esperaba un archivo relativo a PATH_INSTRUCCIONES`).
- **Problema:** la guía del CP2 pasa el Job inicial como `"$PWD/scripts/…"`: el Job terminaba con `ERROR_PLACA` y la prueba no arrancaba.
- **Arreglo:** las rutas absolutas se usan tal cual; las relativas se siguen armando con `PATH_INSTRUCCIONES`.

### 20. Ctrl-C en la Placa, el Planificador y el Core
Ver [[Utils#`cierre.c` / `cierre.h`: Ctrl-C y SIGTERM]].
- **Rama:** `develop` · `9793672` (24/11), pendiente del PR a `main`.
- **Qué fallaba:** los tres módulos morían por la acción por defecto de SIGINT, sin loguear nada.
- **Problema:** en los logs no quedaba registrado por qué terminó el módulo. Además, la señal podía cortar un `accept()`, `recv()` o `usleep()` a mitad de camino.
- **Arreglo:**
  - `utils/cierre.c` bloquea las señales antes de crear los hilos;
  - un hilo las espera con `sigwait()`, loguea `Se recibió SIGINT: el módulo finaliza` y termina con la acción por defecto.
- **Lo que apareció al probarlo:**
  - con `exit()`, la Placa se colgaba, porque su consola tiene tomado el lock de `stdin` (lo mismo pasaría con el Labeler);
  - con `_exit()`, bajo valgrind el proceso no terminaba;
  - por eso se re-envía la señal.

### 21. Logs de error del Storage fuera de INFO
- **Rama:** `develop` (código del Storage) · `b93dfdd` (24/11), pendiente del PR a `main`.
- **Qué fallaba:** `## ERROR - Directorio lleno…` y `## ERROR - Falta de espacio en FAT…` se emitían con `log_error`.
- **Problema:** el enunciado pide que **todos** los logs obligatorios sean `LOG_LEVEL_INFO`; si no, el TP puede considerarse no evaluable.
- **Arreglo:** pasan a `log_info`, con el mismo texto.

### 22. Cores con el mismo ID
- **Rama:** `deploy` · `d7dcf74` (27/11), pendiente de llevar a `develop`.
- **Qué fallaba:** el Planificador no verificaba que el ID de un Core fuera único.
- **Problema:** con dos Cores con el mismo ID, `buscar_core(id)` encontraba siempre el primero. El despacho y la interrupción por quantum podían ir al Core equivocado, y un Job quedaba asignado a un Core que nunca lo recibía. Además, los dos escribían el mismo `core_<id>.log`.
- **Arreglo:** el chequeo del ID, la respuesta del handshake y el alta se hacen juntos bajo `mutex_cores`. Si el ID ya está conectado, el Planificador responde `HANDSHAKE_ERROR`, loguea `Ya hay un Core conectado con el ID N: se rechaza la conexión nueva`, y el Core nuevo termina. Cuando un Core se desconecta, su ID queda libre de nuevo.

---

## Bugs de las herramientas de prueba (`deploy/`)
No afectan a los módulos, pero hacían fallar o colgar las pruebas automáticas.

| Bug | Problema | Arreglo |
| --- | --- | --- |
| `ssh` sin `-n` dentro de un loop | `ssh` se quedaba con la entrada del loop: la consola del Storage recibía solo el primer comando | `ssh -n` |
| Timeout fijo de 300 s | El escenario 02 del CP2 tarda 12 min con los retardos reales | opción `--rapido` y `--timeout` |
| Respuesta del `LABEL` con espera fija | En el CP3 06 se respondía antes de que el otro Job empezara a reemplazar páginas | espera `R<n>` (después de n reemplazos) |
| Mapa de JIDs | Los escenarios de consola usaban el mapa del escenario anterior | se arma uno por escenario |
| Job inicial sin comillas en las finales | El runner no encontraba el Job en el README | `job_del_readme` acepta los dos formatos |
| `read` sin resultado con `set -e` | Cortaba el script en la prueba final 03 | se ignora el código de salida de ese `read` |
| Espera `L<n>` del Loader | Esperaba un inicio nuevo y quedaba colgada si el Loader ya estaba atendiendo | acepta un Loader en curso o pasa a los 20 s |

## Límites conocidos

### Livelock con rangos más grandes que la memoria
**Decisión (25/11):** se documenta como límite del TP y no se corrige.

**Qué pasa** (apareció en el [[Mini Entrenamiento 2026-11-14#Hallazgos|Mini Entrenamiento]]). Una instrucción o syscall cuyo rango necesita, al mismo tiempo, más páginas que marcos tiene la Placa nunca termina. El Job queda en un ciclo page fault → carga → page fault.

Ejemplo: con `TAM_MEMORIA=256` y `TAM_PAGINA=64` (4 marcos), un `LOAD_BATCH` de 512 bytes ocupa 8 páginas. Reproducido el 25/11 con este script:

```
SET CX 512
ALLOC P0 512
LOAD_BATCH lote1 P0 CX
EXIT
```

En 15 segundos hubo 111 page faults y 106 reemplazos, siempre con el propio Job como víctima, y el Job nunca finalizó.

**Por qué pasa.** Son tres reglas del enunciado (Core → Decode → MMU) que se combinan:
1. Todas las traducciones de una instrucción se resuelven **antes** de modificar memoria o registros: el rango tiene que estar completo en memoria a la vez.
2. Las páginas obtenidas quedan **lockeadas**.
3. El Core las **deslockea al devolver el Job** al Planificador (por ejemplo, por un page fault).

Con más páginas que marcos, cada carga desaloja (ya deslockeada) una página que el mismo Job necesita, y el rango nunca llega a estar completo.

**Por qué se deja como límite.**
- **Es una precondición del modelo.** El conjunto de páginas que una instrucción necesita a la vez tiene que entrar en la memoria física. En un sistema operativo real tampoco se puede fijar (*lock*) en memoria más que la memoria física disponible.
- **En teoría es un caso extremo de thrashing.** El conjunto de trabajo de la instrucción es más grande que la memoria: ningún algoritmo de reemplazo lo resuelve, porque siempre falta una página.
- **La cátedra no lo prueba.** En el foro ([#5328](https://github.com/sisoputnfrba/foro/issues/5328)), sobre escenarios con la memoria lockeada, un ayudante respondió que no es un escenario que quieran testear, que las pruebas dejan memoria disponible, y que se puede contemplar con una solución que se justifique desde la teoría.
- **Ninguna prueba lo genera.** Las pruebas finales tienen como mínimo 16 marcos (`TAM_MEMORIA=1024`, `TAM_PAGINA=64`). Las 6 pasan, igual que las suites de CP2 y CP3 (que usan hasta 4 marcos).
- Cambiar las reglas que lo causan (no deslockear en el page fault, o ejecutar el rango por partes) **contradice el enunciado**: mantener las páginas lockeadas mientras el Job está bloqueado además sería *hold and wait*, una de las condiciones de deadlock entre Jobs.

**Impacto si ocurriera.**
- El sistema no se cuelga. El Job afectado alterna entre BLOCKED, READY y EXEC, y los demás Jobs siguen planificándose.
- Sus cargas desalojan páginas de otros Jobs, que van más lento (thrashing).
- Se reconoce en los logs por page faults repetidos del mismo Job con el mismo `Program Counter`.

**Caso relacionado que sí se maneja.** Si hay que cargar una página y todos los marcos están lockeados, la Placa no encuentra víctima y responde `ok=false`. El Job finaliza con `ERROR_PAGE_FAULT`.

**Si la cátedra pidiera corregirlo.** La opción que respeta el enunciado es que la Placa le informe al Core la cantidad de marcos (junto con `OP_TAM_PAGINA`). Antes de traducir, el Core compararía las páginas del rango con los marcos y, si no entran, devolvería el Job con un motivo de error para que el Planificador lo finalice. Está consultado en el foro: [#5335](https://github.com/sisoputnfrba/foro/issues/5335), sin respuesta al 25/11.

### `SIN_ESPACIO_STORAGE` no distingue la causa
El Planificador usa el mismo motivo para "directorio lleno" y para "falta de espacio en FAT", porque `OP_RSP_GUARDAR_CHECKPOINT` solo devuelve `ok`. El Storage sí loguea los dos casos por separado, que es lo que pide el enunciado.
