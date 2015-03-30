/*
 * Apple System Management Control (SMC) Tool
 * Copyright (C) 2006 devnull
 * Portions Copyright (C) 2012 Alex Leigh
 * Portions Copyright (C) 2013 Michael Wilber
 * Portions Copyright (C) 2013 Jedda Wignall
 * Portions Copyright (C) 2014 Perceval Faramaz
 * Portions Copyright (C) 2014 Fergus Morrow
 * Portions Copyright (C) 2014 Naoya Sato
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */
#include <sys/cdefs.h>
#include <Availability.h>

#ifndef __SMC_H__
#define __SMC_H__
#endif

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_INDEX    8
#define SMC_CMD_READ_KEYINFO  9
#define SMC_CMD_READ_PLIMIT   11
#define SMC_CMD_READ_VERS     12

#define DATATYPE_FP1F         "fp1f"
#define DATATYPE_FP4C         "fp4c"
#define DATATYPE_FP5B         "fp5b"
#define DATATYPE_FP6A         "fp6a"
#define DATATYPE_FP79         "fp79"
#define DATATYPE_FP88         "fp88"
#define DATATYPE_FPA6         "fpa6"
#define DATATYPE_FPC4         "fpc4"
#define DATATYPE_FPE2         "fpe2"

#define DATATYPE_SP1E         "sp1e"
#define DATATYPE_SP3C         "sp3c"
#define DATATYPE_SP4B         "sp4b"
#define DATATYPE_SP5A         "sp5a"
#define DATATYPE_SP69         "sp69"
#define DATATYPE_SP78         "sp78"
#define DATATYPE_SP87         "sp87"
#define DATATYPE_SP96         "sp96"
#define DATATYPE_SPB4         "spb4"
#define DATATYPE_SPF0         "spf0"

#define DATATYPE_UINT8        "ui8 "
#define DATATYPE_UINT16       "ui16"
#define DATATYPE_UINT32       "ui32"

#define DATATYPE_SI8          "si8 "
#define DATATYPE_SI16         "si16"

#define DATATYPE_PWM          "{pwm"
#define DATATYPE_LSO          "{lso"
#define DATATYPE_ALA          "{ala"

#define DATATYPE_FLAG         "flag"
#define DATATYPE_CHARSTAR     "ch8*"

typedef char		SMCBytes_t[32];
typedef char		UInt32Char_t[5];
typedef char		Flag[1];
typedef UInt		flag;
typedef UInt16		PWMValue;

typedef struct SMCKeyData_vers_t {
    char                  major;
    char                  minor;
    char                  build;
    char                  reserved[1];
    UInt16                release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16                version;
    UInt16                length;
    UInt32                cpuPLimit;
    UInt32                gpuPLimit;
    UInt32                memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32                dataSize;
    UInt32                dataType;
    char                  dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    UInt32                  key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    char                    result;
    char                    status;
    char                    data8;
    UInt32                  data32;
    SMCBytes_t              bytes;
} SMCKeyData_t;

typedef struct {
    UInt32Char_t            key;
    UInt32                  dataSize;
    UInt32Char_t            dataType;
    SMCBytes_t              bytes;
} SMCVal_t;

typedef enum {
    SUCCESS = 0,
    FAILURE_IOServiceGetMatchingServices = 1,
    FAILURE_NO_SMC_FOUND = 2,
    FAILURE_IOServiceOpen = 3,
    FAILURE_CALLING_STRUCT_METHOD = 4
} SMCState_t;


@interface SMCWrapper : NSObject
+(SMCWrapper *)sharedWrapper;
-(id) init;
-(BOOL) stringRepresentationForBytes: (SMCBytes_t)bytes
							withSize: (UInt32)dataSize
							  ofType: (UInt32Char_t)dataType
							inBuffer: (char *)str;
-(BOOL) stringRepresentationForBytes: (SMCBytes_t)bytes
							withSize: (UInt32)dataSize
							  ofType: (UInt32Char_t)dataType
						  toNSString: (NSString**)abri;
-(BOOL) stringRepresentationOfVal:(SMCVal_t)val
						 inBuffer: (char *)str;
-(BOOL) stringRepresentationOfVal:(SMCVal_t)val
					   toNSString:(NSString**)abri;
#ifndef STRIP_COMPATIBILITY
-(BOOL) getStringRepresentation: (SMCBytes_t)bytes
						forSize: (UInt32)dataSize
						 ofType: (UInt32Char_t)dataType
					   inBuffer: (char *)str
__deprecated_msg("Use stringRepresentationForBytes:withSize:ofType:inBuffer: instead.");
-(BOOL) readKey:(NSString *)key
	   asString:(NSString **)str
__deprecated_msg("Use readKey:intoString: instead.");
#endif
-(BOOL) dumpToValueDict:(NSMutableDictionary**)valDict andTypeDict:(NSMutableDictionary**)typeDict;
-(SMCVal_t) createEmptyValue;
-(BOOL) readKey:(NSString *)key intoVal:(SMCVal_t *)val;
-(BOOL) readKey:(NSString *)key intoString:(NSString **)str;
-(BOOL) readKey:(NSString *)key intoNumber:(NSNumber **)value;
-(void) dealloc;
@end
