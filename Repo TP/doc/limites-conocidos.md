# Límites conocidos

Comportamientos del TP que se conocen y se aceptan como límite, con su justificación. Ver también [planificador.md](planificador.md).

## Livelock con rangos más grandes que la memoria
**Decisión (25/11):** se documenta como límite del TP y no se corrige.

**Qué pasa.** Una instrucción o syscall cuyo rango necesita, al mismo tiempo, más páginas que marcos tiene la Placa nunca termina. El Job queda en un ciclo page fault → carga → page fault.

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

## `SIN_ESPACIO_STORAGE` no distingue la causa
El Planificador usa el mismo motivo para "directorio lleno" y para "falta de espacio en FAT", porque `OP_RSP_GUARDAR_CHECKPOINT` solo devuelve `ok`. El Storage sí loguea los dos casos por separado, que es lo que pide el enunciado.
