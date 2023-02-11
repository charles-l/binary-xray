#include "bfd.h"
#include "stdlib.h"

bfd_vma hack_bfd_asymbol_value(const asymbol *sy) {
    return sy->section->vma + sy->value;
}
