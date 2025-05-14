/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This header file contains structures, type definitions and function declarations
 * for the GCQ driver.
 *
 * @file gcq.h
 *
 */

#ifndef _GCQ_H_
#define _GCQ_H_

#include <stdint.h>
#include <stdio.h>


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#ifndef GCQ_MAX_INSTANCES
#define GCQ_MAX_INSTANCES                       ( 4 )   /**< Default value, but can be overridden by build environmental variable  */
#endif

#ifdef __KERNEL__
#define gcq_assert( x )                                                              \
do {    if ( x ) break;                                                              \
        printk(KERN_EMERG "### ASSERTION FAILED [GCQ Driver] %s: %s: %d: %s\n",      \
               __FILE__, __func__, __LINE__, #x); dump_stack(); BUG();               \
} while ( 0 )

#else
#include <assert.h>
#define gcq_assert( x ) assert( x )

#define likely( x )                             __builtin_expect( !!( x ), 1 )
#define unlikely( x )                           __builtin_expect( !!( x ), 0 )
#endif


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 *
 * @brief   Bound in function ptr for reading from a register
 *
 * @param   ullRegAddr is the register address to be read
 *
 * @return  The 32-bit value read from the register
 *
*******************************************************************************/
typedef uint32_t ( *GCQ_READ_REG_32 )( uint64_t ullRegAddr );

/**
 *
 * @brief   Bound in function ptr for writing to a register
 *
 * @param   ullRegAddr is the register address to write
 * @param   ulvalue is the 32-bit value to write
 *
 * @return  N/A
 *
*******************************************************************************/
typedef void ( *GCQ_WRITE_REG_32 )( uint64_t ullRegAddr, uint32_t ulValue );

/**
 *
 * @brief   Bound in function ptr for reading from a memory address
 *
 * @param   ullMemAddr is the memory address to be read
 *
 * @return  The 32-bit value read from memory
 *
*******************************************************************************/
typedef uint32_t ( *GCQ_READ_MEM_32 )( uint64_t ullMemAddr );

/**
 *
 * @brief   Bound in function for writing to a memory address
 *
 * @param   ullMemAddr is the memory address to be written
 * @param   ulValue is the 32-bit value to write
 *
 * @return  N/A
 *
*******************************************************************************/
typedef void ( *GCQ_WRITE_MEM_32 )( uint64_t ullMemAddr, uint32_t ulValue );


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/*
 * @struct GCQ_INSTANCE_TYPE
 * @brief  Forward declaration of structure to hold a GCQ instance
 */
struct GCQ_INSTANCE_TYPE;

/*
 * @struct GCQ_IO_ACCESS_TYPE
 * @brief  Bound in function pointers for memory & register access
 */
typedef struct GCQ_IO_ACCESS_TYPE
{
    GCQ_READ_REG_32     xGCQReadReg32;
    GCQ_WRITE_REG_32    xGCQWriteReg32;
    GCQ_READ_MEM_32     xGCQReadMem32;
    GCQ_WRITE_MEM_32    xGCQWriteMem32;

} GCQ_IO_ACCESS_TYPE;

typedef struct GCQ_VERSION_TYPE
{
    uint8_t     ucVerMajor;
    uint8_t     ucVerMinor;
    uint8_t     ucVerPatch;
    uint8_t     ucDevCommits;

} GCQ_VERSION_TYPE;


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/*
 * @enum GCQ_ERRORS_TYPE
 * @brief Enumeration of GCQ driver return values
 */
typedef enum GCQ_ERRORS_TYPE
{
    GCQ_ERRORS_NONE = 0,
    GCQ_ERRORS_DRIVER_NOT_INITIALISED,
    GCQ_ERRORS_NO_FREE_INSTANCES,
    GCQ_ERRORS_INVALID_INSTANCE,
    GCQ_ERRORS_INVALID_ARG,
    GCQ_ERRORS_INVALID_SLOT_SIZE,
    GCQ_ERRORS_INVALID_VERSION,
    GCQ_ERRORS_INVALID_NUM_SLOTS,
    GCQ_ERRORS_CONSUMER_NOT_ATTACHED,
    GCQ_ERRORS_CONSUMER_NOT_AVAILABLE,
    GCQ_ERRORS_CONSUMER_NO_DATA_RECEIVED,
    GCQ_ERRORS_PRODUCER_NO_FREE_SLOTS,

    MAX_GCQ_ERRORS_TYPE

} GCQ_ERRORS_TYPE;

/*
 * @enum GCQ_MODE_TYPE
 * @brief Enumeration of GCQ supported modes
 */
typedef enum GCQ_MODE_TYPE
{
    GCQ_MODE_TYPE_CONSUMER_MODE = 0,
    GCQ_MODE_TYPE_PRODUCER_MODE,

    MAX_GCQ_MODE_TYPE

} GCQ_MODE_TYPE;

/*
 * @enum GCQ_INTERRUPT_MODE_TYPE
 * @brief Enumeration of GCQ supported interrupt modes
 */
typedef enum GCQ_INTERRUPT_MODE_TYPE
{
    GCQ_INTERRUPT_MODE_POLLING = 0,
    GCQ_INTERRUPT_MODE_TAIL_POINTER,
    GCQ_INTERRUPT_MODE_INTERRUPT_REG,

    MAX_GCQ_INTERRUPT_MODE

} GCQ_INTERRUPT_MODE_TYPE;

/*
 * @enum GCQ_FLAGS_TYPE
 * @brief Enumeration of GCQ supported driver flags to enable
 *        relevant functionality
 */
typedef enum GCQ_FLAGS_TYPE
{
    /*
     * Extra flags used to support features/hacks required
     * for specific platforms
     */
    GCQ_FLAGS_TYPE_DOUBLE_READ_ENABLE  = ( 1 << 0 ),
    GCQ_FLAGS_TYPE_IN_MEM_PTR_ENABLE   = ( 1 << 1 ),

    MAX_GCQ_FLAGS_TYPE

} GCQ_FLAGS_TYPE;


/******************************************************************************/
/* Driver External APIs                                                       */
/******************************************************************************/

/**
 *
 * @brief    Initialise the GCQ standalone driver
 *           Internally the function will:
 *           - Allocate an internal instance if any are free
 *           - Calculate the number of slots required
 *           - Validate there is enough shared memory
 *           - Initialise the internal ring buffers for the producer
 *           - Write the magic metadata to the producer
 *           - Handle the extended driver functionality flags
 *
 * @param    ppxGCQInstance is the instance of the of the GCQ returned by driver
 * @param    pxIOAccess is the bound in function pointers for memory & register access
 * @param    xMode is the supported mode, consumer or producer
 * @param    xIntMode is the supported interrupt mode
 * @param    xFlags is the extended driver functionality
 * @param    ullBaseAddr is the base address of the GCQ IP block
 * @param    ullRingAddr is the base address of the shared memory for allocating slots
 * @param    ullRingLen is the length of the shared memory provided
 * @param    ulSQSlotSize is the required submission queue (SQ) slot size
 * @param    ulCQSlotSize is the required completion queue (CQ) slot size
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 *
 */
GCQ_ERRORS_TYPE xGCQInit( struct GCQ_INSTANCE_TYPE **ppxGCQInstance,
                          const GCQ_IO_ACCESS_TYPE *pxIOAccess,
                          GCQ_MODE_TYPE xMode,
                          GCQ_INTERRUPT_MODE_TYPE xIntMode,
                          GCQ_FLAGS_TYPE xFlags,
                          uint64_t ullBaseAddr,
                          uint64_t ullRingAddr,
                          uint64_t ullRingLen,
                          uint32_t ulSQSlotSize,
                          uint32_t ulCQSlotSize );

/**
 *
 * @brief    De-initialise a GCQ driver instance
 *
 * @param    ppxGCQInstance is the instance to de-initialise
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 *
 */
GCQ_ERRORS_TYPE xGCQDeinit( struct GCQ_INSTANCE_TYPE *pxGCQInstance );

/**
 *
 * @brief    Attempt to attach to the consumer, needs to be called before
 *           data can be consumed.
 *           Internally the function will:
 *           - Check driver has been initilaised
 *           - Check for consumer ring buffer for the magic metadata
 *           - Check the internal version matches
 *           - Prepare the ring buffer to receive data
 *
 * @param    pxGCQInstance is the instance of the GCQ
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 *
 */
GCQ_ERRORS_TYPE xGCQAttachConsumer( struct GCQ_INSTANCE_TYPE *pxGCQInstance );

/**
 *
 * @brief    Function to consume/read data from the GCQ
 *           Internally the function will:
 *           - Check driver has been initilaised
 *           - Check driver has attached to the consumer
 *           - Attempt to read data if any is available
 *
 * @param    pxGCQInstance is the instance of the GCQ
 * @param    pucData is the pointer to the data to be populated on receive
 * @param    ulDatalLen is the length of the data received
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 *
 */
GCQ_ERRORS_TYPE xGCQConsumeData( struct GCQ_INSTANCE_TYPE *pxGCQInstance, uint8_t *pucData, uint32_t ulDatalLen );

/**
 *
 * @brief    Function to produce/send data to the GCQ
 *           Internally the function will:
 *           - Check driver has been initilaised
 *           - Attempt to send data
 *
 * @param    pxGCQInstance is the instance of the GCQ
 * @param    pucData is the pointer to be data to be sent
 * @param    ulDataLen the length of the data being sent
 *
 * @return   See GCQ_ERRORS_TYPE for possible return values
 *
 */
GCQ_ERRORS_TYPE xGCQProduceData( struct GCQ_INSTANCE_TYPE *pxGCQInstance, uint8_t *pucData, uint32_t ulDataLen );

/**
 *
 * @brief    Gets version information from gcq_version.h
 *
 * @return   OK                  Version set successfully
 *           ERROR               Version not set successfully
 *
 */
int iGCQGetVersion( GCQ_VERSION_TYPE *pxVersion );

#endif /* _GCQ_H_ */
