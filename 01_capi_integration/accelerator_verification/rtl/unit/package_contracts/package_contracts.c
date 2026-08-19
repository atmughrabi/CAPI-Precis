#include <stddef.h>
#include <sys/types.h>

#include "capienv.h"

_Static_assert(sizeof(void *) == 8, "CAPI host ABI requires 64-bit pointers");
_Static_assert(sizeof(struct WEDStruct) == 128, "WEDStruct must be 128 bytes");
_Static_assert(sizeof(struct WEDStructTut) == 128, "WEDStructTut must be 128 bytes");
_Static_assert(sizeof(struct WEDStructMM) == 128, "WEDStructMM must be 128 bytes");
_Static_assert(offsetof(struct WEDStruct, size_send) == 0, "WED size_send offset");
_Static_assert(offsetof(struct WEDStruct, array_send) == 16, "WED array_send offset");
_Static_assert(offsetof(struct WEDStruct, pointer12) == 120, "WED pointer12 offset");
_Static_assert(offsetof(struct WEDStructTut, size_send) == 0, "Tutorial size offset");
_Static_assert(offsetof(struct WEDStructTut, array_send) == 16, "Tutorial array offset");
_Static_assert(offsetof(struct WEDStructTut, pointer12) == 120, "Tutorial tail offset");
_Static_assert(offsetof(struct WEDStructMM, size_n) == 0, "Matrix size offset");
_Static_assert(offsetof(struct WEDStructMM, A) == 16, "Matrix A offset");
_Static_assert(offsetof(struct WEDStructMM, pointer2) == 40, "Matrix pointer2 offset");
_Static_assert(offsetof(struct WEDStructMM, pointer12) == 120, "Matrix tail offset");

int main(void)
{
    return 0;
}
