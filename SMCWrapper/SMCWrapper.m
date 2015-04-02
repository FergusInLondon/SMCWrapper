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

#include "SMCWrapper.h"

//#define STRIP_COMPATIBILIY

// AppleSMC IOService connection
io_connect_t conn;
// Shared Instance (Singleton)
static SMCWrapper *sharedInstance = nil;

@interface SMCWrapper() //private methods
-(BOOL) _smcOpen;
-(BOOL) _smcClose;
-(kern_return_t) _smcCall:(int)index
			   forKeyData:(SMCKeyData_t *)inputStructure
				toKeyData:(SMCKeyData_t *)outputStructure;
-(kern_return_t) _smcReadKey:(UInt32Char_t)key toValue:(SMCVal_t*)val;
-(UInt32) _strtoul:(char *)str
		   forSize:(int)size
			inBase:(int)base;
-(void) _ultostr:(char *)str
		forValue:(UInt32)val;
-(UInt32) _smcIndexCount;

#ifndef STRIP_COMPATIBILITY
-(kern_return_t) SMCReadKey:(UInt32Char_t)key
				outputValue:(SMCVal_t *)val
__deprecated_msg("Use _smcReadKey:toValue: instead.");
-(kern_return_t) SMCCall:(int)index
			  forKeyData:(SMCKeyData_t *)inputStructure
		 outputKeyDataIn:(SMCKeyData_t *)outputStructure
__deprecated_msg("Use _smcCall:forKeyData: toKeyData: instead.");
#endif
@end

@implementation SMCWrapper
/**
 * sharedWrapper - Singleton instance retrieval method. Used to get an instance of SMCWrapper.
 */
+(SMCWrapper *) sharedWrapper{
	if ( sharedInstance == nil ){
		sharedInstance = [[SMCWrapper alloc] init];
	}
	return sharedInstance;
}
/**
 * _smcOpen - Opens a connection (&conn) to the AppleSMC IOService.
 *
 * (a) Retrieve the master-port to allow RPC calls with I/O Kit.
 * (b) Attempt to get the "AppleSMC" IOService;
 *    - IOServiceMatching returns a CFMutableDictionaryRef of any matching services;
 *    - IOServiceGetMatchingServices then looks up these actual services,
 *       allowing us to iterate through them
 *    - We then connect to the first matching service (via IOSericeOpen)
 */
-(BOOL) _smcOpen
{
	kern_return_t result;
	mach_port_t   masterPort;
	io_iterator_t iterator;
	io_object_t   device;
	
	result = IOMasterPort(MACH_PORT_NULL, &masterPort);
	
	CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
	result = IOServiceGetMatchingServices(masterPort, matchingDictionary, &iterator);
	if (result != kIOReturnSuccess)
	{
		printf("Error: IOServiceGetMatchingServices() = %08x\n", result);
		return NO;
	}
	
	device = IOIteratorNext(iterator);
	IOObjectRelease(iterator);
	if (device == 0)
	{
		printf("Error: no SMC found\n");
		return NO;
	}
	
	result = IOServiceOpen(device, mach_task_self(), 0, &conn);
	IOObjectRelease(device);
	if (result != kIOReturnSuccess)
	{
		printf("Error: IOServiceOpen() = %08x\n", result);
		return NO;
	}
	return YES;
}

/**
 * _smcClose - Closes connections to the AppleSMC IOService.
 */
-(BOOL) _smcClose
{
	kern_return_t result = IOServiceClose(conn);
	if (result == KERN_SUCCESS)
		return true;
	else
		return false;
}

/**
 * _strtoul:forSize:inBase - Takes C string (char *) and generates an Unsigned
 *  Integer (32bit) by treating each individual char as an 8bit value. Acts in
 *  the opposite to _ultostr.
 */
-(UInt32) _strtoul:(char *)str
		   forSize:(int)size
			inBase:(int)base
{
	UInt32 total = 0;
	int i;
	
	for (i = 0; i < size; i++)
	{
		if (base == 16)
			total += str[i] << (size - 1 - i) * 8;
		else
			total += (unsigned char) (str[i] << (size - 1 - i) * 8);
	}
	return total;
}

/**
 * _ultostr:str:forValue - Takes a reference C string (char *) and an Unsigned
 *  Integer (32bit), and creates a string representation (char[4]) of the
 *  integer. (Essentially breaking the 32bit Integer in to an array of 4 8bit
 *  values)
 */
-(void) _ultostr:(char *)str
		forValue:(UInt32)val
{
	str[0] = '\0';
	sprintf(str, "%c%c%c%c",
			(unsigned int) val >> 24,
			(unsigned int) val >> 16,
			(unsigned int) val >> 8,
			(unsigned int) val);
}

/**
 * _smcCall:forKeyData:toKeyData - A wrapper method around
 *  IOConnectCallStructMethod - which is responsible for IOService calls.
 */
-(kern_return_t) _smcCall:(int)index
			   forKeyData:(SMCKeyData_t *)inputStructure
				toKeyData:(SMCKeyData_t *)outputStructure
{
	size_t   structureInputSize;
	size_t   structureOutputSize;
	
	structureInputSize = sizeof(SMCKeyData_t);
	structureOutputSize = sizeof(SMCKeyData_t);
	
	return IOConnectCallStructMethod( conn, index,
									 // inputStructure
									 inputStructure, structureInputSize,
									 // ouputStructure
									 outputStructure, &structureOutputSize );
}

/**
 * _smcReadKey:toValue - Reads an SMCKey (UInt32Char/char[5]), by
 *  populating and maintaining to SMCKeyData structures and utilising SMCCall.
 */
-(kern_return_t) _smcReadKey:(UInt32Char_t)key toValue:(SMCVal_t*)val
{
	kern_return_t result;
	SMCKeyData_t  inputStructure;
	SMCKeyData_t  outputStructure;
	
	memset(&inputStructure, 0, sizeof(SMCKeyData_t));
	memset(&outputStructure, 0, sizeof(SMCKeyData_t));
	memset(val, 0, sizeof(SMCVal_t));
	
	inputStructure.key = [self _strtoul:key forSize:4 inBase:16];
	inputStructure.data8 = SMC_CMD_READ_KEYINFO;
	
	result = [self _smcCall: KERNEL_INDEX_SMC
				 forKeyData: &inputStructure
				  toKeyData: &outputStructure];
	if (result != kIOReturnSuccess)
		return result;
	
	val->dataSize = outputStructure.keyInfo.dataSize;
	[self _ultostr:val->dataType forValue:outputStructure.keyInfo.dataType];
	inputStructure.keyInfo.dataSize = val->dataSize;
	inputStructure.data8 = SMC_CMD_READ_BYTES;
	
	result = [self _smcCall:KERNEL_INDEX_SMC forKeyData:&inputStructure toKeyData:&outputStructure];
	if (result != kIOReturnSuccess)
		return result;
	
	memcpy(val->bytes, outputStructure.bytes, sizeof(outputStructure.bytes));
	
	return kIOReturnSuccess;
}

#ifdef WRITE_ABILITY
-(kern_return_t) _smcWriteKey:(SMCVal_t)writeVal
{
	kern_return_t result;
	SMCKeyData_t  inputStructure;
	SMCKeyData_t  outputStructure;
	
	SMCVal_t      readVal;
	
	result = [self _smcReadKey:writeVal.key toValue:&readVal];
	if (result != kIOReturnSuccess)
		return result;
	
	if (readVal.dataSize != writeVal.dataSize) {
		//return kIOReturnError;
		writeVal.dataSize = readVal.dataSize;
	}
	
	memset(&inputStructure, 0, sizeof(SMCKeyData_t));
	memset(&outputStructure, 0, sizeof(SMCKeyData_t));
	
	inputStructure.key = [self _strtoul:writeVal.key forSize:4 inBase:16];
	inputStructure.data8 = SMC_CMD_WRITE_BYTES;
	inputStructure.keyInfo.dataSize = writeVal.dataSize;
	memcpy(inputStructure.bytes, writeVal.bytes, sizeof(writeVal.bytes));
	
	result = [self _smcCall:KERNEL_INDEX_SMC forKeyData:&inputStructure toKeyData:&outputStructure];
	if (result != kIOReturnSuccess)
		return result;
	
	return kIOReturnSuccess;
}
#endif

/**
 * _smcIndexCount - Retrieves the number of keys stored in SMC
 */
-(UInt32) _smcIndexCount {
	SMCVal_t val;
	int num = 0;
	
	[self _smcReadKey:"#KEY" toValue:&val]; //reads the key index count
	num = ((int)val.bytes[2] << 8) + ((unsigned)val.bytes[3] & 0xff);
	return num;
}

#ifndef STRIP_COMPATIBILITY
-(kern_return_t) SMCReadKey:(UInt32Char_t)key
				outputValue:(SMCVal_t *)val
{
	return [self _smcReadKey:key toValue:val];
}
-(kern_return_t) SMCCall:(int)index
			  forKeyData:(SMCKeyData_t *)inputStructure
		 outputKeyDataIn:(SMCKeyData_t *)outputStructure
{
	return [self _smcCall:index forKeyData:inputStructure toKeyData:outputStructure];
}
-(BOOL) readKey:(NSString *)key asString:(NSString **)str
{
	return [self readKey:key intoString:str];
}
-(BOOL) getStringRepresentation: (SMCBytes_t)bytes
						forSize: (UInt32)dataSize
						 ofType: (UInt32Char_t)dataType
					   inBuffer: (char *)str {
	return [self stringRepresentationForBytes:bytes withSize:dataSize ofType:dataType inBuffer:str];
}
#endif

/**
 * createEmptyValue - Initiates an empty SMCVal_t value
 */
-(SMCVal_t) createEmptyValue {
	SMCVal_t newVal;
	memset(&newVal, 0, sizeof(newVal));
	return newVal;
}

/**
 * stringRepresentationForBytes:withSize:ofType:inBuffer - Retrieves a CString
 *  representation of the given values ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRepresentationForBytes: (SMCBytes_t)bytes
							withSize: (UInt32)dataSize
							  ofType: (UInt32Char_t)dataType
							inBuffer: (char *)str
{
	if (dataSize > 0) {
		if ((strcmp(dataType, DATATYPE_UINT8) == 0) ||
			(strcmp(dataType, DATATYPE_UINT16) == 0) ||
			(strcmp(dataType, DATATYPE_UINT32) == 0)) {
			UInt32 uint= [self _strtoul:bytes forSize:dataSize inBase:10];
			snprintf(str, 15, "%u ", (unsigned int)uint);
		}
		else if (strcmp(dataType, DATATYPE_FP1F) == 0 && dataSize == 2)
			snprintf(str, 15, "%.5f ", ntohs(*(UInt16*)bytes) / 32768.0);
		else if (strcmp(dataType, DATATYPE_FP4C) == 0 && dataSize == 2)
			snprintf(str, 15, "%.5f ", ntohs(*(UInt16*)bytes) / 4096.0);
		else if (strcmp(dataType, DATATYPE_FP5B) == 0 && dataSize == 2)
			snprintf(str, 15, "%.5f ", ntohs(*(UInt16*)bytes) / 2048.0);
		else if (strcmp(dataType, DATATYPE_FP6A) == 0 && dataSize == 2)
			snprintf(str, 15, "%.4f ", ntohs(*(UInt16*)bytes) / 1024.0);
		else if (strcmp(dataType, DATATYPE_FP79) == 0 && dataSize == 2)
			snprintf(str, 15, "%.4f ", ntohs(*(UInt16*)bytes) / 512.0);
		else if (strcmp(dataType, DATATYPE_FP88) == 0 && dataSize == 2)
			snprintf(str, 15, "%.3f ", ntohs(*(UInt16*)bytes) / 256.0);
		else if (strcmp(dataType, DATATYPE_FPA6) == 0 && dataSize == 2)
			snprintf(str, 15, "%.2f ", ntohs(*(UInt16*)bytes) / 64.0);
		else if (strcmp(dataType, DATATYPE_FPC4) == 0 && dataSize == 2)
			snprintf(str, 15, "%.2f ", ntohs(*(UInt16*)bytes) / 16.0);
		else if (strcmp(dataType, DATATYPE_FPE2) == 0 && dataSize == 2)
			snprintf(str, 15, "%.2f ", ntohs(*(UInt16*)bytes) / 4.0);
		else if (strcmp(dataType, DATATYPE_SP1E) == 0 && dataSize == 2)
			snprintf(str, 15, "%.5f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 16384.0);
		else if (strcmp(dataType, DATATYPE_SP3C) == 0 && dataSize == 2)
			snprintf(str, 15, "%.5f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 4096.0);
		else if (strcmp(dataType, DATATYPE_SP4B) == 0 && dataSize == 2)
			snprintf(str, 15, "%.4f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 2048.0);
		else if (strcmp(dataType, DATATYPE_SP5A) == 0 && dataSize == 2)
			snprintf(str, 15, "%.4f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 1024.0);
		else if (strcmp(dataType, DATATYPE_SP69) == 0 && dataSize == 2)
			snprintf(str, 15, "%.3f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 512.0);
		else if (strcmp(dataType, DATATYPE_SP78) == 0/* && dataSize == 2*/)
			snprintf(str, 15, "%.3f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 256.0);
		else if (strcmp(dataType, DATATYPE_SP87) == 0 && dataSize == 2)
			snprintf(str, 15, "%.3f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 128.0);
		else if (strcmp(dataType, DATATYPE_SP96) == 0 && dataSize == 2)
			snprintf(str, 15, "%.2f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 64.0);
		else if (strcmp(dataType, DATATYPE_SPB4) == 0 && dataSize == 2)
			snprintf(str, 15, "%.2f ", ((SInt16)ntohs(*(UInt16*)bytes)) / 16.0);
		else if (strcmp(dataType, DATATYPE_SPF0) == 0 && dataSize == 2)
			snprintf(str, 15, "%.0f ", (float)ntohs(*(UInt16*)bytes));
		else if (strcmp(dataType, DATATYPE_SI16) == 0 && dataSize == 2)
			snprintf(str, 15, "%d ", ntohs(*(SInt16*)bytes));
		else if (strcmp(dataType, DATATYPE_SI8) == 0 && dataSize == 1)
			snprintf(str, 15, "%d ", (signed char)*bytes);
		else if (strcmp(dataType, DATATYPE_PWM) == 0 && dataSize == 2)
			snprintf(str, 15, "%.1f%% ", ntohs(*(UInt16*)bytes) * 100 / 65536.0);
		else if (strcmp(dataType, DATATYPE_CHARSTAR) == 0)
			snprintf(str, 15, "%s ", bytes);
		else if (strcmp(dataType, DATATYPE_FLAG) == 0)
			snprintf(str, 15, "%s ", bytes[0] ? "TRUE" : "FALSE");
		else {
			int i;
			char tempAb[64];
			for (i = 0; i < dataSize; i++) {
				snprintf(tempAb+strlen(tempAb), 8, "%02x ", (unsigned char) bytes[i]);
			}
			snprintf(str, 15, "%s ", tempAb);
		}
		return TRUE;
	}
	return FALSE;
}

/**
 * stringRepresentationForBytes:withSize:ofType:intoString - Retrieves a NSString
 *  representation of the given values ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRepresentationForBytes: (SMCBytes_t)bytes
							withSize: (UInt32)dataSize
							  ofType: (UInt32Char_t)dataType
						  intoString: (NSString**)abri
{
	if (dataSize > 0) {
		if ((strcmp(dataType, DATATYPE_UINT8) == 0) ||
			(strcmp(dataType, DATATYPE_UINT16) == 0) ||
			(strcmp(dataType, DATATYPE_UINT32) == 0))
			*abri = [[NSString alloc] initWithFormat:@"%u", (unsigned int)[self _strtoul:(char *)bytes forSize:dataSize inBase:10]];
		else if (strcmp(dataType, DATATYPE_FP1F) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.5f", (ntohs(*(UInt16*)bytes) / 32768.0)];
		else if (strcmp(dataType, DATATYPE_FP4C) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.5f", (ntohs(*(UInt16*)bytes) / 4096.0)];
		else if (strcmp(dataType, DATATYPE_FP5B) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.5f", (ntohs(*(UInt16*)bytes) / 2048.0)];
		else if (strcmp(dataType, DATATYPE_FP6A) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.4f", (ntohs(*(UInt16*)bytes) / 1024.0)];
		else if (strcmp(dataType, DATATYPE_FP79) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.4f", (ntohs(*(UInt16*)bytes) / 512.0)];
		else if (strcmp(dataType, DATATYPE_FP88) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.3f", (ntohs(*(UInt16*)bytes) / 256.0)];
		else if (strcmp(dataType, DATATYPE_FPA6) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.2f", (ntohs(*(UInt16*)bytes) / 64.0)];
		else if (strcmp(dataType, DATATYPE_FPC4) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.2f", (ntohs(*(UInt16*)bytes) / 16.0)];
		else if (strcmp(dataType, DATATYPE_FPE2) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.2f", (ntohs(*(UInt16*)bytes) / 4.0)];
		else if (strcmp(dataType, DATATYPE_SP1E) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.5f", (((SInt16)ntohs(*(UInt16*)bytes)) / 16384.0)];
		else if (strcmp(dataType, DATATYPE_SP3C) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.5f", (((SInt16)ntohs(*(UInt16*)bytes)) / 4096.0)];
		else if (strcmp(dataType, DATATYPE_SP4B) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.4f", (((SInt16)ntohs(*(UInt16*)bytes)) / 2048.0)];
		else if (strcmp(dataType, DATATYPE_SP5A) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.4f", (((SInt16)ntohs(*(UInt16*)bytes)) / 1024.0)];
		else if (strcmp(dataType, DATATYPE_SP69) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.3f", (((SInt16)ntohs(*(UInt16*)bytes)) / 512.0)];
		else if (strcmp(dataType, DATATYPE_SP78) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.3f", (((SInt16)ntohs(*(UInt16*)bytes)) / 256.0)];
		else if (strcmp(dataType, DATATYPE_SP87) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.3f", (((SInt16)ntohs(*(UInt16*)bytes)) / 128.0)];
		else if (strcmp(dataType, DATATYPE_SP96) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.2f", (((SInt16)ntohs(*(UInt16*)bytes)) / 64.0)];
		else if (strcmp(dataType, DATATYPE_SPB4) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.2f", (((SInt16)ntohs(*(UInt16*)bytes)) / 16.0)];
		else if (strcmp(dataType, DATATYPE_SPF0) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.0f", ((float)ntohs(*(UInt16*)bytes))];
		else if (strcmp(dataType, DATATYPE_SI8) == 0 && dataSize == 1)
			*abri = [[NSString alloc] initWithFormat:@"%d", ((signed char)*bytes)];
		else if (strcmp(dataType, DATATYPE_SI16) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%d", (ntohs(*(SInt16*)bytes))];
		else if (strcmp(dataType, DATATYPE_PWM) == 0 && dataSize == 2)
			*abri = [[NSString alloc] initWithFormat:@"%.1f%%", (ntohs(*(UInt16*)bytes) * 100 / 65536.0)];
		else if (strcmp(dataType, DATATYPE_CHARSTAR) == 0) {
			*abri = [[NSString alloc] initWithFormat:@"%s", bytes];
		}
		else if (strcmp(dataType, DATATYPE_FLAG) == 0)
			*abri = [[NSString alloc] initWithFormat:@"%s", bytes[0] ? "TRUE" : "FALSE"];
		else {
			int i;
			char tempAb[64];
			for (i = 0; i < dataSize; i++) {
				snprintf(tempAb+strlen(tempAb), 8, "%02x ", (unsigned char) bytes[i]);
			}
			*abri = [[NSString alloc] initWithFormat:@"%s", tempAb];
		}
		return TRUE;
	}
	return FALSE;
}

/**
 * stringRawRepresentationForBytes:withSize:ofType:intoString - Retrieves a NSString raw (hex bytes)
 *  representation of the given values ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRawRepresentationForBytes: (SMCBytes_t)bytes
							   withSize: (UInt32)dataSize
								 ofType: (UInt32Char_t)dataType
							 intoString: (NSString**)abri
{
	if (dataSize > 0) {
		int i;
		char tempAb[64];
		for (i = 0; i < dataSize; i++) {
			snprintf(tempAb+strlen(tempAb), 8, "%02x ", (unsigned char) bytes[i]);
		}
		*abri = [[NSString alloc] initWithFormat:@"%s", tempAb];
		return TRUE;
	}
	return FALSE;
}

/**
 * stringRawRepresentationForBytes:withSize:ofType:inBuffer - Retrieves a CString raw (hex bytes)
 *  representation of the given values ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRawRepresentationForBytes: (SMCBytes_t)bytes
							   withSize: (UInt32)dataSize
								 ofType: (UInt32Char_t)dataType
							   inBuffer: (char *)str
{
	if (dataSize > 0) {
		int i;
		char tempAb[64];
		for (i = 0; i < dataSize; i++) {
			snprintf(tempAb+strlen(tempAb), 8, "%02x ", (unsigned char) bytes[i]);
		}
		snprintf(str, 15, "%s ", tempAb);
		return TRUE;
	}
	return FALSE;
}

/**
 * stringRepresentationOfVal:inBuffer: - Retrieves a CString representation
 * of the given SMCVal_t ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRepresentationOfVal:(SMCVal_t)val
						 inBuffer: (char *)str
{
	return [self stringRepresentationForBytes:val.bytes withSize:val.dataSize ofType:val.dataType inBuffer:str];
}

/**
 * stringRepresentationOfVal:intoString: - Retrieves a NSString representation
 * of the given SMCVal_t ; returns a bool to indicate success or failure.
 */
-(BOOL) stringRepresentationOfVal:(SMCVal_t)val
					   intoString:(NSString**)abri
{
	return [self stringRepresentationForBytes:val.bytes withSize:val.dataSize ofType:val.dataType intoString:abri];
}

/**
 * stringRawRepresentationOfVal:inBuffer: - Retrieves a NSString representation
 * of the given SMCVal_t raw value (hex bytes); returns a bool to indicate success or failure.
 */
-(BOOL) stringRawRepresentationOfVal:(SMCVal_t)val
							inBuffer:(char *)str
{
	return [self stringRepresentationForBytes:val.bytes withSize:val.dataSize ofType:val.dataType inBuffer:str];
}

/**
 * stringRawRepresentationOfVal:intoString: - Retrieves a NSString representation
 * of the given SMCVal_t raw value (hex bytes); returns a bool to indicate success or failure.
 */
-(BOOL) stringRawRepresentationOfVal:(SMCVal_t)val
						  intoString:(NSString**)abri
{
	return [self stringRepresentationForBytes:val.bytes withSize:val.dataSize ofType:val.dataType intoString:abri];
}

/**
 * stringRawRepresentationOfVal:intoString: - Retrieves a NSString representation
 * of the given SMCVal_t raw value (hex bytes); returns a bool to indicate success or failure.
 */
-(BOOL) typeOfVal:(SMCVal_t)val intoString:(NSString **)str
{
	if (val.dataType) { //check if belongs to type array
		*str = [[NSString alloc] initWithCString:val.dataType encoding:NSUTF8StringEncoding];
		return TRUE;
	}
	return FALSE;
}

/**
 * readKey:intoVal - Wrapper for the internal _smcReadKey that fills the given SMCVal_t,
 * taking a NSString (not a CString) as the key name; returns a bool to indicate success or failure.
 */
-(BOOL) readKey:(NSString *)key intoVal:(SMCVal_t *)val {
	kern_return_t result;
	
	result = [self _smcReadKey:(char*)[key UTF8String] toValue: val];
	// Do value checking on val.
	if (result != kIOReturnSuccess) {
		return NO;
	}
	return YES;
}

/**
 * readKey:intoString - Reads a given key from the SMC and formats the corresponding
 *  value as an NSString (passed by reference). Returns a BOOL indicating success.
 */
-(BOOL) readKey:(NSString *)key intoString:(NSString **)str
{
	char cStr[16];   // Something has gone majorly wrong if it's over 15 digits long.
	SMCVal_t val;
	kern_return_t result;
	
	result = [self _smcReadKey:(char*)[key UTF8String] toValue: &val];
	
	// Do value checking on val.
	if (result != kIOReturnSuccess) {
		*str = [[NSString alloc] initWithFormat:@""];
		return NO;
	}
	
	// Mac OS X means rubbish FourCC style data type referencing
	[self stringRepresentationForBytes:val.bytes
							  withSize:val.dataSize
								ofType:val.dataType
							  inBuffer:&cStr[0]];
	
	*str = [[NSString alloc] initWithCString:cStr encoding:NSUTF8StringEncoding];
	return YES;
}

/**
 * readKey:intoNumber - Reads a given key from the SMC and formats the corresponding
 *  value as an NSNumber (passed by reference). Returns a BOOL indicating success.
 */
-(BOOL) readKey:(NSString *)key intoNumber:(NSNumber **)value
{
	NSString *stringVal;
	NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
	NSNumber *num;
	num = [NSNumber numberWithInt:0];
 
	if (! [self readKey:key intoString:&stringVal] ){
		num = [NSNumber numberWithInt:0];
		*value = num;
		return NO;
	}
	
	[f setNumberStyle:NSNumberFormatterDecimalStyle];
	num = [f numberFromString:stringVal];
	*value = num;
	return YES;
}

-(BOOL) dumpToValueDict:(NSMutableDictionary**)valDict andTypeDict:(NSMutableDictionary**)typeDict {
	kern_return_t result;
	SMCKeyData_t  inputStructure;
	SMCKeyData_t  outputStructure;
	
	int           totalKeys=0, i=0;
	UInt32Char_t  key;
	SMCVal_t      val;
	NSString* stringKey;
	NSString* valueKey;
	NSString* typeKey;
	*valDict=[[NSMutableDictionary alloc] init];
	*typeDict=[[NSMutableDictionary alloc] init];
	totalKeys = [self _smcIndexCount];
	for (i = 0; i < totalKeys; i++) {
		//zeroing out structures
		memset(&inputStructure, 0, sizeof(SMCKeyData_t));
		memset(&outputStructure, 0, sizeof(SMCKeyData_t));
		memset(&val, 0, sizeof(SMCVal_t));
		//setting parameters in structures (to read the name of the key we're looking for, by its ID, which here is =i)
		inputStructure.data8 = SMC_CMD_READ_INDEX;
		inputStructure.data32 = i;
		
		//makes call to AppleSMC IOService
		result = [self _smcCall:KERNEL_INDEX_SMC forKeyData:&inputStructure toKeyData:&outputStructure];
		if (result != kIOReturnSuccess)
			continue;
		
		[self _ultostr:key forValue:outputStructure.key];
		
		result = [self _smcReadKey:key toValue:&val]; //reads key (by its name, see above)
		stringKey = [NSString stringWithFormat:@"%s" , key];
		[self stringRepresentationOfVal:val intoString:&valueKey];
		
		typeKey = [NSString stringWithFormat:@"%-4s",val.dataType];
		[*valDict setObject:valueKey forKey:stringKey];
		[*typeDict setObject:typeKey forKey:stringKey];
	}
	return TRUE;
}

-(id) init
{
	self = [super init];
	if (self) {
		[self _smcOpen]; //open connection to AppleSMC IOService
	}
	return self;
}

-(void) dealloc
{
	[self _smcClose]; //closes connection to AppleSMC IOService
}

@end
