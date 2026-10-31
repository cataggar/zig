typedef int16_t int_fast16_t;
typedef int32_t int_fast32_t;
typedef uint16_t uint_fast16_t;
typedef uint32_t uint_fast32_t;

#define INT_FAST16_MIN  INT16_MIN
#define INT_FAST32_MIN  INT32_MIN

#define INT_FAST16_MAX  INT16_MAX
#define INT_FAST32_MAX  INT32_MAX

#define UINT_FAST16_MAX UINT16_MAX
#define UINT_FAST32_MAX UINT32_MAX

#if defined(__wasm64__)
#undef INT64_MIN
#undef INT64_MAX
#undef UINT64_MAX
#define INT64_MIN       (-1-0x7fffffffffffffffLL)
#define INT64_MAX       (0x7fffffffffffffffLL)
#define UINT64_MAX      (0xffffffffffffffffULL)
#define INTPTR_MIN      (-1-0x7fffffffffffffffL)
#define INTPTR_MAX      (0x7fffffffffffffffL)
#define UINTPTR_MAX     (0xffffffffffffffffUL)
#define PTRDIFF_MIN     (-1-0x7fffffffffffffffL)
#define PTRDIFF_MAX     (0x7fffffffffffffffL)
#define SIZE_MAX        (0xffffffffffffffffUL)
#else
#define INTPTR_MIN      INT32_MIN
#define INTPTR_MAX      INT32_MAX
#define UINTPTR_MAX     UINT32_MAX
#define PTRDIFF_MIN     INT32_MIN
#define PTRDIFF_MAX     INT32_MAX
#define SIZE_MAX        UINT32_MAX
#endif
