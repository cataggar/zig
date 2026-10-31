#if defined(__wasm64__)
#define _POSIX_V6_LP64_OFF64  1
#define _POSIX_V7_LP64_OFF64  1
#else
#define _POSIX_V6_ILP32_OFFBIG (1)
#define _POSIX_V7_ILP32_OFFBIG (1)
#endif
