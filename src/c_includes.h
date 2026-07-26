#ifndef C_INCLUDES_H
#define C_INCLUDES_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "sqlite3.h"
#define SQLITE_EXTENSION_INIT1
#include "sqlite3ext.h"

#define U_DISABLE_RENAMING 1
#include <unicode/utypes.h>
#include <unicode/ustring.h>
#include <unicode/ubrk.h>
#include <unicode/utrans.h>
#include <unicode/uchar.h>

#endif
