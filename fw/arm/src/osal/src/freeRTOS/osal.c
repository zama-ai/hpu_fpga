/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the (OSAL) API implementation for FreeRTOS.
 *
 * @file osal_FreeRTOS.c
 *
 */

/*****************************************************************************/
/* Includes                                                                  */
/*****************************************************************************/

/* Standard includes */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Xil includes */
#include "xil_printf.h"

/* FreeRTOS includes */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "timers.h"
#include "event_groups.h"

/* AMC includes */
#include "osal.h"
#include "standard.h"


/*****************************************************************************/
/* Defines                                                                   */
/*****************************************************************************/

#ifndef OSAL_MAX_TASKS
#define OSAL_MAX_TASKS              ( 10 )
#endif

#ifndef OSAL_TASK_MAX_STACK_SIZE
#define OSAL_TASK_MAX_STACK_SIZE    ( 0x2000 / sizeof( StackType_t ) )
#endif

#define MEM_UNUSED                  ( 0 )
#define MEM_USED                    ( 1 )
#define DEFAULT_TASK_PRIORITY       ( 5 )
#define CHECK_32BIT_ALIGNMENT( x )  ( 0 == ( x & 0x3 ) )
#define RETURN_IF_OS_NOT_STARTED    if( TRUE != iOsStarted ) return OSAL_ERRORS_OS_NOT_STARTED
#define BINARY_SEM_BUCKET_SIZE      ( 1 )
#define PRINT_BUFFER_SIZE           ( 256 )
#define ONE_TICK                    ( 1 )
#define DEFAULT_TIMER_BLOCK_TIME_MS ( 1000 )
#define DEFAULT_TIMER_PERIOD_MS     ( 100 )
#define DEFAULT_OS_NAME             ( "freeRTOS" )
#define LINE_SEPARATOR              ( "--------------------------------------------------------------------------------------------------------------------------\r\n" )


/*****************************************************************************/
/* Structs                                                                   */
/*****************************************************************************/

/**
 * @struct OSAL_TASK_MEMORY
 * 
 * @brief Struct to store task's stack, TCB (Task control block) and handle. 
 *        Used for static task allocation.
 */
typedef struct OSAL_TASK_MEMORY
{
    StackType_t xStack[ OSAL_TASK_MAX_STACK_SIZE ];
    StaticTask_t xTcb;
    TaskHandle_t xTaskHandle;

} OSAL_TASK_MEMORY;


/*****************************************************************************/
/* Local Variables                                                           */
/*****************************************************************************/

static int iRoundRobinScheduler   = FALSE;
static int iOsStarted             = FALSE;
static void *pvPrintfMutexHandle  = NULL;
static void *pvGetCharMutexHandle = NULL;
static void *pvMemSetSemHandle    = NULL;
static void *pvMemCpySemHandle    = NULL;
static void *pvStrNCpySemHandle   = NULL;
static void *pvMemCmpSemHandle    = NULL;
static void *pvMemMoveSemHandle   = NULL;

static OSAL_TASK_MEMORY xTaskMemoryPool[ OSAL_MAX_TASKS ] = { 0 };
static BaseType_t xTaskMemoryUsed[ OSAL_MAX_TASKS ]       = { 0 }; /* 0 - unused, 1 - used */


/*****************************************************************************/
/* Debug stats structs                                                       */
/*****************************************************************************/

typedef struct OSAL_TASK_STATS_LINKED_LIST
{
    void* pvTask;
    char* pcName;
    char* pcStatus;
    uint16_t usTaskStackSize;
    uint32_t ulTaskPriority;
    uint16_t usTaskStackWaterMark;
    uint32_t ulCpuUsagePercentage;
    struct OSAL_TASK_STATS_LINKED_LIST* pxNext;

} OSAL_TASK_STATS_LINKED_LIST;

typedef struct OSAL_SEM_STATS_LINKED_LIST
{
    void* pvSem;
    char* pcName;
    int iPostCount;
    int iPendCount;
    char* pcStatus;
    struct OSAL_SEM_STATS_LINKED_LIST* pxNext;

} OSAL_SEM_STATS_LINKED_LIST;

typedef struct OSAL_MUTEX_STATS_LINKED_LIST
{
    void* pvMutex;
    char* pcName;
    int iTakeCount;
    int iReleaseCount;
    char* pcStatus;
    struct OSAL_MUTEX_STATS_LINKED_LIST* pxNext;

} OSAL_MUTEX_STATS_LINKED_LIST;

typedef struct OSAL_MBOX_STATS_LINKED_LIST
{
    void* pvMailbox;
    char* pcName;
    uint32_t ulMBoxLength;
    uint32_t ulItemSize;
    int iTxCount;
    int iRxCount;
    int iItemCount;
    char* pcStatus;
    struct OSAL_MBOX_STATS_LINKED_LIST* pxNext;

} OSAL_MBOX_STATS_LINKED_LIST;

typedef struct OSAL_EVENT_STATS_LINKED_LIST
{
    void* pvEvent;
    char* pcName;
    uint32_t ulFlagWait;
    uint32_t ulFlagSet;
    char* pcStatus;
    struct OSAL_EVENT_STATS_LINKED_LIST* pxNext;

} OSAL_EVENT_STATS_LINKED_LIST;

typedef struct OSAL_TIMER_STATS_LINKED_LIST
{
    void* pvTimer;
    char* pcName;
    char* pcType;
    uint32_t ulDurationMs;
    int iRunCount;
    char* pcStatus;
    struct OSAL_TIMER_STATS_LINKED_LIST* pxNext;

} OSAL_TIMER_STATS_LINKED_LIST;

typedef struct OSAL_OS_STATS
{
    struct OSAL_TASK_STATS_LINKED_LIST *pxTaskHead;
    struct OSAL_SEM_STATS_LINKED_LIST *pxSemHead;
    struct OSAL_MUTEX_STATS_LINKED_LIST *pxMutexHead;
    struct OSAL_MBOX_STATS_LINKED_LIST *pxMailboxHead;
    struct OSAL_EVENT_STATS_LINKED_LIST *pxEventHead;
    struct OSAL_TIMER_STATS_LINKED_LIST *pxTimerHead;
    struct OSAL_MEMORY_STATS_LINKED_LIST *pxMemHead;

    int iMemAllocCallCount;
    int iMemFreeCallCount;

} OSAL_OS_STATS;

static OSAL_OS_STATS xOsStatsHandle = 
{
    NULL,   /* pxTaskHead */
    NULL,   /* pxSemHead */
    NULL,   /* pxMutexHead */
    NULL,   /* pxMailboxHead */
    NULL,   /* pxEventHead */
    NULL,   /* pxTimerHead */
    NULL,   /* pxMemHead */

    0,      /* iMemAllocCallCount */
    0      /* iMemFreeCallCount */
};

static OSAL_OS_STATS * pxOsStatsHandle = &xOsStatsHandle;


/******************************************************************************/
/* Local Function Declarations                                                */
/******************************************************************************/

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvTaskHandle Task handle to search for.
 *
 * @return OSAL_TASK_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_TASK_STATS_LINKED_LIST* pxFindTask( void* pvTaskHandle );

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvSemHandle Sem handle to search for.
 *
 * @return OSAL_SEM_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_SEM_STATS_LINKED_LIST* pxFindSem( void* pvSemHandle );

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvMutexHandle Mutex handle to search for.
 *
 * @return OSAL_MUTEX_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_MUTEX_STATS_LINKED_LIST* pxFindMutex( void* pvMutexHandle );

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvMailboxHandle Mailbox handle to search for.
 *
 * @return OSAL_MBOX_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_MBOX_STATS_LINKED_LIST* pxFindMailbox( void* pvMailboxHandle );

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvEventHandle Event handle to search for.
 *
 * @return OSAL_EVENT_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_EVENT_STATS_LINKED_LIST* pxFindEvent( void* pvEventHandle );

/**
 * @brief Searches the linked list for the given key.
 *
 * @param pvTimerHandle Timer handle to search for.
 *
 * @return OSAL_TIMER_STATS_LINKED_LIST* Linked List node that matches the given key, NULL if no match found.
 */
static OSAL_TIMER_STATS_LINKED_LIST* pxFindTimer( void* pvTimerHandle );

/**
 * @brief Prints debug stats header.
 *
 * @param pcType Debug stats type name.
 */
static void vPrint_Header( const char* pcType );

/**
 * @brief Prints debug stats footer.
 *
 * @param iCount Item count to display in the footer.
 * @param pcType Stat name to display in the footer.
 */
static void vPrint_Footer( int iCount, const char* pcType );

/**
 * @brief Prints OS debug stats.
 *
 */
static void vPrint_OS_Stats( void );

/**
 * @brief Prints Task debug stats.
 *
 * @param eVerbosity Level of debug verbosity.
 */
static void vPrint_Task_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Semaphore debug stats.
 *
 * @param eVerbosity Level of debug verbosity.
 */
static void vPrint_Sem_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Mutex debug stats.
 *
 * @param eVerbosity Level of debug verbosity.
 */
static void vPrint_Mutex_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Mailbox debug stats.
 *
 * @param eVerbosity Level of debug verbosity.
 */
static void vPrint_Mailbox_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Event debug stats.
 *
 * @param eVerbosity Level of debug verbosity.
 */
static void vPrint_Event_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Timer debug stats.
 */
static void vPrint_Timer_Stats( OSAL_STATS_VERBOSITY eVerbosity );

/**
 * @brief Prints Memory debug stats.
 */
static void vPrint_Memory_Stats( void );

/**
 * @brief Calculates the deepest point the stack has reached ( the closer this is to 0, the closer the task has come to overflowing its stack )
 */
static void vCalculateStackWatermark( void );

/**
 * @brief Calculates the CPU usage of active tasks.
 */
#ifdef FREERTOS_DEBUG
static void vCalculateCpuUsage( void );
#endif

/**
 * @brief FreeRTOS Macro used to configure a timer for run-time stats.
 *
 */
void vConfigureTimerForRunTimeStats( void );

/**
 * @brief FreeRTOS Macro used to get cycle count for run-time stats.
 *
 * @returns uint32_t Cycle counter value.
*/
uint32_t vGetRunTimeCounterValue( void );

/**
 * @brief Allocates memory for a new task from the memory pool.
 *
 * @returns Pointer to a struct that holds the new tasks stack and TCB.
*/
static OSAL_TASK_MEMORY* pxAllocateTaskMemory( void );

/**
 * @brief Frees up task memory when it is no longer needed.
 *
 * @param pxMemory Pointer to the struct that needs free'd.
*/
static void vDeallocateTaskMemory( OSAL_TASK_MEMORY* pxMemory );


/*****************************************************************************/
/* Function implementations                                                  */
/*****************************************************************************/

/*****************************************************************************/
/* Public APIs                                                               */
/*****************************************************************************/

/**
 * @brief   This function will return OS type and version information for the OSAL
 *          implementation being used.
 */
int iOSAL_GetOsVersion( char pcOs[ OSAL_OS_NAME_LEN ],
                        uint8_t* pucVersionMajor,
                        uint8_t* pucVersionMinor,
                        uint8_t* pucVersionBuild )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    if( ( NULL != pcOs ) &&
        ( NULL != pucVersionMajor ) &&
        ( NULL != pucVersionMinor ) &&
        ( NULL != pucVersionBuild ) )
    {
        char pcOsName[ OSAL_OS_NAME_LEN ] = DEFAULT_OS_NAME;

        pvOSAL_MemCpy( ( void* )pcOs, ( void* )pcOsName, OSAL_OS_NAME_LEN );

        *pucVersionMajor = tskKERNEL_VERSION_MAJOR;
        *pucVersionMinor = tskKERNEL_VERSION_MINOR;
        *pucVersionBuild = tskKERNEL_VERSION_BUILD;

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}


/*****************************************************************************/
/* Scheduler APIs                                                            */
/*****************************************************************************/

/* TODO: change all ms conversions to use pdMS_TO_TICKS */

/**
 * @brief   Start the RTOS scheduler.
 */
int iOSAL_StartOS( int         iRoundRobinEnabled,
                   void**      ppvTaskHandle,
                   void        ( *pvStartTask )( void ),
                   uint16_t    usStartTaskStackSize,
                   uint32_t    ulStartTaskPriority )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    if( ( TRUE >= iRoundRobinEnabled ) &&
        ( NULL != ppvTaskHandle      ) &&
        ( NULL != pvStartTask        ) &&
        ( 0 != usStartTaskStackSize  ) &&
        ( CHECK_32BIT_ALIGNMENT( usStartTaskStackSize ) ) &&
        ( FALSE == iOsStarted ) &&
        ( NULL == pvPrintfMutexHandle  ) &&
        ( NULL == pvGetCharMutexHandle ) &&
        ( NULL == pvMemSetSemHandle    ) &&
        ( NULL == pvMemCpySemHandle    ) &&
        ( NULL == pvStrNCpySemHandle   ) && 
        ( NULL == pvMemCmpSemHandle    ) &&
        ( NULL == pvMemMoveSemHandle   ) )
    {
        iRoundRobinScheduler = iRoundRobinEnabled;

        if( TRUE == iRoundRobinScheduler )
        {
            /* Over-ride task priority */
            ulStartTaskPriority = DEFAULT_TASK_PRIORITY;
        }

        /* convert stack size in bytes to words ( num bytes / stack width ) */
        usStartTaskStackSize =  usStartTaskStackSize / sizeof( StackType_t );

        /* Try to allocate a stack from the memory pool */
        OSAL_TASK_MEMORY *pxMemory = pxAllocateTaskMemory();

        if( NULL != pxMemory )
        {
            *ppvTaskHandle = xTaskCreateStatic( ( TaskFunction_t )pvStartTask,
                                                "OSAL Main Task",
                                                ( configSTACK_DEPTH_TYPE )usStartTaskStackSize,
                                                NULL,
                                                ( UBaseType_t )ulStartTaskPriority,
                                                pxMemory->xStack,
                                                &pxMemory->xTcb );

            if( NULL != *ppvTaskHandle )
            {
                pxMemory->xTaskHandle = *ppvTaskHandle;

                /* Task created successfully, create thread safe mutexes and binary semaphores */
                pvPrintfMutexHandle  = xSemaphoreCreateMutex();
                pvGetCharMutexHandle = xSemaphoreCreateMutex();
                pvMemSetSemHandle  = xSemaphoreCreateBinary();
                pvMemCpySemHandle  = xSemaphoreCreateBinary();
                pvMemCmpSemHandle  = xSemaphoreCreateBinary();
                pvStrNCpySemHandle = xSemaphoreCreateBinary();
                pvMemMoveSemHandle = xSemaphoreCreateBinary();

                if( ( NULL != pvPrintfMutexHandle  ) &&
                    ( NULL != pvGetCharMutexHandle ) &&
                    ( NULL != pvMemSetSemHandle    ) &&
                    ( NULL != pvMemCpySemHandle    ) &&
                    ( NULL != pvStrNCpySemHandle   ) &&
                    ( NULL != pvMemCmpSemHandle    ) &&
                    ( NULL != pvMemMoveSemHandle   ) )
                {
                    xSemaphoreGive( ( SemaphoreHandle_t ) pvMemSetSemHandle );
                    xSemaphoreGive( ( SemaphoreHandle_t ) pvMemCpySemHandle );
                    xSemaphoreGive( ( SemaphoreHandle_t ) pvMemCmpSemHandle );
                    xSemaphoreGive( ( SemaphoreHandle_t ) pvStrNCpySemHandle );
                    xSemaphoreGive( ( SemaphoreHandle_t ) pvMemMoveSemHandle );
                    /* Mutexes and binary semaphores created successfully, start scheduler */
                    iOsStarted = TRUE;
                    iStatus = OSAL_ERRORS_NONE;

                    /* Initialising OS struct */
                    pxOsStatsHandle = ( OSAL_OS_STATS* ) pvPortMalloc( sizeof( OSAL_OS_STATS ) );
                    if( NULL != pxOsStatsHandle )
                    {
                        pxOsStatsHandle->pxTaskHead = NULL;
                        pxOsStatsHandle->pxMutexHead = NULL;
                        pxOsStatsHandle->pxSemHead = NULL;
                        pxOsStatsHandle->pxMailboxHead = NULL;
                        pxOsStatsHandle->pxTimerHead = NULL;
                        pxOsStatsHandle->pxEventHead = NULL;
                        pxOsStatsHandle->pxMemHead = NULL;

                        pxOsStatsHandle->iMemAllocCallCount = 0;
                        pxOsStatsHandle->iMemFreeCallCount  = 0;

                        /* Adding main task to linked list */
                        OSAL_TASK_STATS_LINKED_LIST *pxNewNode = ( OSAL_TASK_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_TASK_STATS_LINKED_LIST ) );
                        if( NULL != pxNewNode )
                        {
                            pxNewNode->pvTask = *ppvTaskHandle;

                            pxNewNode->pcName = strdup( "OSAL Main Task" );
                            pxNewNode->pcStatus = strdup( "Active" );
                            pxNewNode->usTaskStackSize = usStartTaskStackSize * sizeof( StackType_t );
                            pxNewNode->ulTaskPriority = ulStartTaskPriority;

                            pxNewNode->usTaskStackWaterMark = 0;
                            pxNewNode->ulCpuUsagePercentage = 0;
                            pxNewNode->pxNext = pxOsStatsHandle->pxTaskHead;
                            pxOsStatsHandle->pxTaskHead = pxNewNode;
                        }
                    }

                    vTaskStartScheduler();
                    /* if this returns, not enough memory */
                    iStatus = OSAL_ERRORS_INSUFFICIENT_MEM;
                }
                else
                {
                    /* Mutex not created */
                    iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
                }
            }
            else
            {
                /* Task not created */
                iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
            }
        }
        else
        {
            vDeallocateTaskMemory( pxMemory );

            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Returns tick count since OS was initialised.
 */
uint32_t ulOSAL_GetUptimeTicks( void )
{
    RETURN_IF_OS_NOT_STARTED;

    TickType_t xUpTimeTicks = xTaskGetTickCount();

    return ( uint32_t )xUpTimeTicks;
}

/**
 * @brief   Returns ms count since OS was initialised.
 */
uint32_t ulOSAL_GetUptimeMs( void )
{
    RETURN_IF_OS_NOT_STARTED;

    TickType_t xUpTimeTicks = xTaskGetTickCount();
    uint32_t ulUpTimeMs = ( ( uint32_t )xUpTimeTicks / pdMS_TO_TICKS( 1 ) );

    return ulUpTimeMs;
}

/**
 * @brief   Returns tick count since OS was initialised, from ISR.
 */
uint32_t ulOSAL_GetUptimeTicksFromISR( void )
{
    RETURN_IF_OS_NOT_STARTED;

    TickType_t xUpTimeTicks = xTaskGetTickCountFromISR();

    return ( uint32_t )xUpTimeTicks;
}

/**
 * @brief   Returns ms count since OS was initialised, from ISR.
 */
uint32_t ulOSAL_GetUptimeMsFromISR( void )
{
    RETURN_IF_OS_NOT_STARTED;

    TickType_t xUpTimeTicks = xTaskGetTickCountFromISR();
    uint32_t ulUpTimeMs = ( ( uint32_t )xUpTimeTicks / pdMS_TO_TICKS( 1 ) );

    return ulUpTimeMs;
}


/*****************************************************************************/
/* Task APIs                                                                 */
/*****************************************************************************/

/**
 * @brief   Create a new OSAL task.
 */
int iOSAL_Task_Create( void**      ppvTaskHandle,
                       void        ( *pvTaskFunction )( void* pvTaskParam ),
                       uint16_t    usTaskStackSize,
                       void*       pvTaskParam,
                       uint32_t    ulTaskPriority,
                       const char* pcTaskName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvTaskHandle  ) &&
        ( NULL != pvTaskFunction ) &&
        ( 0 != usTaskStackSize   ) &&
        ( CHECK_32BIT_ALIGNMENT( usTaskStackSize ) ) &&
        ( NULL != pcTaskName ) )
    {
        if( TRUE == iRoundRobinScheduler )
        {
            /* Over-ride task priority */
            ulTaskPriority = DEFAULT_TASK_PRIORITY;
        }

        /* convert stack size in bytes to words ( num bytes / stack width ) */
        usTaskStackSize = usTaskStackSize / sizeof( StackType_t );

        /* Try to allocate a stack from the memory pool */
        OSAL_TASK_MEMORY* pxMemory = pxAllocateTaskMemory();

        if( NULL != pxMemory )
        {
            *ppvTaskHandle = xTaskCreateStatic( ( TaskFunction_t )pvTaskFunction,
                                                pcTaskName,
                                                ( configSTACK_DEPTH_TYPE )usTaskStackSize,
                                                pvTaskParam,
                                                ( UBaseType_t )ulTaskPriority,
                                                pxMemory->xStack,
                                                &pxMemory->xTcb );

            if( NULL != *ppvTaskHandle )
            {
                pxMemory->xTaskHandle = *ppvTaskHandle;

                /* Add task to debug stats */
                OSAL_TASK_STATS_LINKED_LIST *pxNewNode = ( OSAL_TASK_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_TASK_STATS_LINKED_LIST ) );
                if( NULL != pxNewNode )
                {
                    pxNewNode->pvTask = *ppvTaskHandle;

                    pxNewNode->pcName = strdup( pcTaskName );
                    pxNewNode->pcStatus = strdup( "Active" );
                    pxNewNode->usTaskStackSize = usTaskStackSize * sizeof( StackType_t );
                    pxNewNode->ulTaskPriority = ulTaskPriority;

                    pxNewNode->usTaskStackWaterMark = 0;
                    pxNewNode->ulCpuUsagePercentage = 0;
                    pxNewNode->pxNext = pxOsStatsHandle->pxTaskHead;
                    pxOsStatsHandle->pxTaskHead = pxNewNode;
                }

                /* Task created successfully */
                iStatus = OSAL_ERRORS_NONE;
            }
            else
            {
                iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
            }
        }
        else
        {
            vDeallocateTaskMemory( pxMemory );

            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Remove OSAL task from RTOS Kernal.
 */
int iOSAL_Task_Delete( void** ppvTaskHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvTaskHandle ) &&
        ( NULL != *ppvTaskHandle ) )
    {
        OSAL_TASK_STATS_LINKED_LIST *pxCurrent = pxFindTask( *ppvTaskHandle );

        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        TaskHandle_t xTaskToDelete = ( TaskHandle_t )*ppvTaskHandle;
        OSAL_TASK_MEMORY* pxMemory = NULL;

        for( int i = 0; i < OSAL_MAX_TASKS; i++ )
        {
            if( xTaskMemoryPool[ i ].xTaskHandle == xTaskToDelete )
            {
                pxMemory = &xTaskMemoryPool[ i ];
                break;
            }
        }

        vTaskDelete( xTaskToDelete );

        if( NULL != *ppvTaskHandle )
        {
            *ppvTaskHandle = NULL;
        }

        if ( NULL != pxMemory )
        {
            vDeallocateTaskMemory( pxMemory );
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Suspend any OSAL task.
 */
int iOSAL_Task_Suspend( void* pvTaskHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvTaskHandle )
    {
        vTaskSuspend( ( TaskHandle_t )pvTaskHandle );

        OSAL_TASK_STATS_LINKED_LIST *pxCurrent = pxFindTask( pvTaskHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Suspended" );
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Resume any OSAL task.
 */
int iOSAL_Task_Resume( void* pvTaskHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvTaskHandle )
    {
        vTaskResume( ( TaskHandle_t )pvTaskHandle );

        OSAL_TASK_STATS_LINKED_LIST *pxCurrent = pxFindTask( pvTaskHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Active" );
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Delay a task for a given number of ticks.
 */
int iOSAL_Task_SleepTicks( uint32_t ulSleepTicks )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( 0 < ulSleepTicks )
    {
        vTaskDelay( ( TickType_t )ulSleepTicks );
        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Delay a task for a given number of ms.
 */
int iOSAL_Task_SleepMs( uint32_t ulSleepMs )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( 0 < ulSleepMs )
    {
        TickType_t xSleepTicks = pdMS_TO_TICKS( ulSleepMs );

        if( 0 == xSleepTicks )
        {
            xSleepTicks = ONE_TICK;
        }

        vTaskDelay( xSleepTicks );
        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}


/*****************************************************************************/
/* Semaphore APIs                                                            */
/*****************************************************************************/

/**
 * @brief   Creates a binary or counting semaphore, and sets OS Semaphore Handle by which the semaphore can be referenced.
 */
int iOSAL_Semaphore_Create( void** ppvSemHandle,
                            uint32_t ullCount,
                            uint32_t ullBucket,
                            const char* pcSemName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvSemHandle  ) &&
        ( NULL == *ppvSemHandle ) &&
        ( NULL != pcSemName ) )
    {
        *ppvSemHandle = xSemaphoreCreateCounting( ( UBaseType_t )ullBucket,
                                                  ( UBaseType_t )ullCount );

        if( NULL != *ppvSemHandle )
        {
            /* Add semaphore to debug stats */
            OSAL_SEM_STATS_LINKED_LIST *pxNewNode = ( OSAL_SEM_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_SEM_STATS_LINKED_LIST ) );
            if( NULL != pxNewNode )
            {
                pxNewNode->pvSem = *ppvSemHandle;
                pxNewNode->pcName = strdup( pcSemName );
                pxNewNode->iPostCount = 0;
                pxNewNode->iPendCount = 0;
                pxNewNode->pcStatus = strdup( "Active" );

                pxNewNode->pxNext = pxOsStatsHandle->pxSemHead;
                pxOsStatsHandle->pxSemHead = pxNewNode;
            }

            /* Semaphore created successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
        else
        {
            /* Semaphore not created */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Deletes the binary or counting semaphore, to which the handle refers.
 */
int iOSAL_Semaphore_Destroy( void** ppvSemHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvSemHandle  ) &&
        ( NULL != *ppvSemHandle ) )
    {
        OSAL_SEM_STATS_LINKED_LIST *pxCurrent = pxFindSem( *ppvSemHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        vSemaphoreDelete( ( SemaphoreHandle_t )*ppvSemHandle );

        if( NULL != *ppvSemHandle )
        {
            *ppvSemHandle = NULL;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Pends to / obtains a previously created semaphore, to which the handle refers.
 */
int iOSAL_Semaphore_Pend( void* pvSemHandle, uint32_t ulTimeoutMs )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvSemHandle )
    {
        TickType_t xTimeoutTicks = 0;

        if( OSAL_TIMEOUT_WAIT_FOREVER == ulTimeoutMs )
        {
            xTimeoutTicks = portMAX_DELAY;
        }
        else if( OSAL_TIMEOUT_NO_WAIT == ulTimeoutMs )
        {
            xTimeoutTicks = 0;
        }
        else
        {
            xTimeoutTicks = pdMS_TO_TICKS( ulTimeoutMs );

            if( 0 == xTimeoutTicks )
            {
                xTimeoutTicks = ONE_TICK;
            }
        }

        if( pdPASS != xSemaphoreTake( ( SemaphoreHandle_t )pvSemHandle, xTimeoutTicks ) )
        {
            /* Semaphore not taken */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {

            OSAL_SEM_STATS_LINKED_LIST *pxCurrent = pxFindSem( pvSemHandle );
            if( NULL != pxCurrent)
            {
                pxCurrent->iPendCount++;
            }

            /* Semaphore taken successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Posts / Releases a previously created semaphore, to which the handle refers.
 */
int iOSAL_Semaphore_Post( void* pvSemHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvSemHandle )
    {
        if( pdPASS != xSemaphoreGive( ( SemaphoreHandle_t )pvSemHandle ) )
        {
            /* Semaphore not released */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            OSAL_SEM_STATS_LINKED_LIST *pxCurrent = pxFindSem( pvSemHandle );
            if( NULL != pxCurrent)
            {
                pxCurrent->iPostCount++;
            }

            /* Semaphore released successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   A version of iOSAL_Semaphore_Post() that can be called from an ISR.
 */
int iOSAL_Semaphore_PostFromISR( void* pvSemHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvSemHandle )
    {
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;

        if( pdPASS != xSemaphoreGiveFromISR( ( SemaphoreHandle_t )pvSemHandle,
                                             &xHigherPriorityTaskWoken ) )
        {
            /* Semaphore not released */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Semaphore released successfully */
            iStatus = OSAL_ERRORS_NONE;
        }

        if( pdTRUE == xHigherPriorityTaskWoken )
        {
            /* macro used here is port specific.*/
            portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Mutex APIs                                                                */
/*****************************************************************************/

/**
 * @brief   Creates a Mutex, and sets OS Mutex Handle by which the Mutex can be referenced.
 */
int iOSAL_Mutex_Create( void**      ppvMutexHandle,
                        const char* pcMutexName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvMutexHandle  ) &&
        ( NULL == *ppvMutexHandle ) &&
        ( NULL != pcMutexName ) )
    {
        *ppvMutexHandle = xSemaphoreCreateMutex();

        if( NULL != *ppvMutexHandle )
        {
            /* Add mutex to debug stats */
            OSAL_MUTEX_STATS_LINKED_LIST *pxNewNode = ( OSAL_MUTEX_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_SEM_STATS_LINKED_LIST ) );
            if( NULL != pxNewNode )
            {
                pxNewNode->pvMutex = *ppvMutexHandle;
                pxNewNode->pcName = strdup( pcMutexName );
                pxNewNode->iTakeCount = 0;
                pxNewNode->iReleaseCount = 0;
                pxNewNode->pcStatus = strdup( "Active" );

                pxNewNode->pxNext = pxOsStatsHandle->pxMutexHead;
                pxOsStatsHandle->pxMutexHead = pxNewNode;
            }

            /* Mutex created successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
        else
        {
            /* Mutex not created */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Deletes a Mutex, to which the handle refers.
 */
int iOSAL_Mutex_Destroy( void** ppvMutexHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvMutexHandle  ) &&
        ( NULL != *ppvMutexHandle ) )
    {
        OSAL_MUTEX_STATS_LINKED_LIST *pxCurrent = pxFindMutex( *ppvMutexHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        vSemaphoreDelete( ( SemaphoreHandle_t )*ppvMutexHandle );

        if( NULL != *ppvMutexHandle )
        {
            *ppvMutexHandle = NULL;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Obtains a previously created Mutex, to which the handle refers.
 */
int iOSAL_Mutex_Take( void*    pvMutexHandle,
                      uint32_t ulTimeoutMs )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvMutexHandle )
    {
        TickType_t xTimeoutTicks = 0;
        BaseType_t xReturn = pdFAIL;

        if( OSAL_TIMEOUT_WAIT_FOREVER == ulTimeoutMs )
        {
            xTimeoutTicks = portMAX_DELAY;
        }
        else if( OSAL_TIMEOUT_NO_WAIT == ulTimeoutMs )
        {
            xTimeoutTicks = 0;
        }
        else
        {
            xTimeoutTicks = pdMS_TO_TICKS( ulTimeoutMs );

            if( 0 == xTimeoutTicks )
            {
                xTimeoutTicks = ONE_TICK;
            }
        }

        xReturn = xSemaphoreTake( ( SemaphoreHandle_t )pvMutexHandle, xTimeoutTicks );

        if( pdPASS != xReturn )
        {
            /* Mutex not taken */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            OSAL_MUTEX_STATS_LINKED_LIST *pxCurrent = pxFindMutex( pvMutexHandle);
            if( NULL != pxCurrent)
            {
                pxCurrent->iTakeCount++;
            }

            /* Mutex taken successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Releases a previously created Mutex, to which the handle refers.
 */
int iOSAL_Mutex_Release( void* pvMutexHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvMutexHandle )
    {
        BaseType_t xReturn = pdFAIL;

        xReturn = xSemaphoreGive( ( SemaphoreHandle_t )pvMutexHandle );

        if( pdPASS != xReturn )
        {
            /* Mutex not released */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            OSAL_MUTEX_STATS_LINKED_LIST *pxCurrent = pxFindMutex( pvMutexHandle);
            if( NULL != pxCurrent)
            {
                pxCurrent->iReleaseCount++;
            }

            /* Mutex released successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Mailbox APIs                                                              */
/*****************************************************************************/

/**
 * @brief   Creates a new MailBox, and sets OS MailBox Handle by which the MailBox can be referenced.
 */
int iOSAL_MBox_Create( void**      ppvMBoxHandle,
                       uint32_t    ulMBoxLength,
                       uint32_t    ulItemSize,
                       const char* pcMBoxName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvMBoxHandle  ) &&
        ( NULL == *ppvMBoxHandle ) &&
        ( NULL != pcMBoxName     ) )
    {
        *ppvMBoxHandle = xQueueCreate( ( UBaseType_t )ulMBoxLength,
                                       ( UBaseType_t )ulItemSize );

        if( NULL != *ppvMBoxHandle )
        {
            /* Add mbox to debug stats */
            OSAL_MBOX_STATS_LINKED_LIST *pxNewNode = ( OSAL_MBOX_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_MBOX_STATS_LINKED_LIST ) );
            if( NULL != pxNewNode )
            {
                pxNewNode->pvMailbox = *ppvMBoxHandle;
                pxNewNode->pcName = strdup( pcMBoxName );
                pxNewNode->iRxCount = 0;
                pxNewNode->iTxCount = 0;
                pxNewNode->iItemCount = 0;
                pxNewNode->ulMBoxLength = ulMBoxLength;
                pxNewNode->ulItemSize = ulItemSize;
                pxNewNode->pcStatus = strdup( "Active" );

                pxNewNode->pxNext = pxOsStatsHandle->pxMailboxHead;
                pxOsStatsHandle->pxMailboxHead = pxNewNode;
            }

            /* MBox created successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
        else
        {
            /* MBox not created */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Resets a MailBox, to which the handle refers.
 */
int iOSAL_MBox_Destroy( void** ppvMBoxHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvMBoxHandle  ) &&
        ( NULL != *ppvMBoxHandle ) )
    {
        OSAL_MBOX_STATS_LINKED_LIST *pxCurrent = pxFindMailbox( *ppvMBoxHandle);
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        vQueueDelete( ( QueueHandle_t )*ppvMBoxHandle );

        if( NULL != *ppvMBoxHandle )
        {
            *ppvMBoxHandle = NULL;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Recieve an item from a message Mailbox, to which the handle refers.
 */
int iOSAL_MBox_Pend( void*    pvMBoxHandle,
                     void*    pvMBoxBuffer,
                     uint32_t ulTimeoutMs )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != pvMBoxHandle ) &&
        ( NULL != pvMBoxBuffer ) )
    {
        TickType_t xTimeoutTicks = 0;
        BaseType_t xReturn = pdFAIL;

        if( OSAL_TIMEOUT_WAIT_FOREVER == ulTimeoutMs )
        {
            xTimeoutTicks = portMAX_DELAY;
        }
        else if( OSAL_TIMEOUT_NO_WAIT == ulTimeoutMs )
        {
            xTimeoutTicks = 0;
        }
        else
        {
            xTimeoutTicks = pdMS_TO_TICKS( ulTimeoutMs );

            if( 0 == xTimeoutTicks )
            {
                xTimeoutTicks = ONE_TICK;
            }
        }

        xReturn = xQueueReceive( ( QueueHandle_t )pvMBoxHandle,
                                    pvMBoxBuffer,
                                    xTimeoutTicks );

        if( pdPASS != xReturn )
        {
            /* Item not recieved */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            OSAL_MBOX_STATS_LINKED_LIST *pxCurrent = pxFindMailbox( pvMBoxHandle );
            if( NULL != pxCurrent)
            {
                pxCurrent->iRxCount++;
                pxCurrent->iItemCount--;
            }

            /* Item recieved successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Posts an item onto a MailBox, to which the handle refers.
 */
int iOSAL_MBox_Post( void*    pvMBoxHandle,
                     void*    pvMBoxItem,
                     uint32_t ulTimeoutMs )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != pvMBoxHandle ) &&
        ( NULL != pvMBoxItem   ) )
    {
        TickType_t xTimeoutTicks = 0;
        BaseType_t xReturn = pdFAIL;

        if( OSAL_TIMEOUT_WAIT_FOREVER == ulTimeoutMs )
        {
            xTimeoutTicks = portMAX_DELAY;
        }
        else if( OSAL_TIMEOUT_NO_WAIT == ulTimeoutMs )
        {
            xTimeoutTicks = 0;
        }
        else
        {
            xTimeoutTicks = pdMS_TO_TICKS( ulTimeoutMs );

            if( 0 == xTimeoutTicks )
            {
                xTimeoutTicks = ONE_TICK;
            }
        }

        xReturn = xQueueSend( ( QueueHandle_t )pvMBoxHandle,
                                pvMBoxItem,
                                xTimeoutTicks );

        if( pdPASS != xReturn )
        {
            /* Item not posted - MBox full */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            OSAL_MBOX_STATS_LINKED_LIST *pxCurrent = pxFindMailbox( pvMBoxHandle );
            if( NULL != pxCurrent)
            {
                pxCurrent->iTxCount++;
                pxCurrent->iItemCount++;
            }

            /* Item posted successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   A version of iOSAL_MBox_Post() that can be called from an ISR.
 */
int iOSAL_MBox_PostFromISR( void* pvMBoxHandle, void* pvMBoxItem )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != pvMBoxHandle ) &&
        ( NULL != pvMBoxItem   ) )
    {
        BaseType_t xReturn = pdFAIL;
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;

        xReturn = xQueueSendFromISR( ( QueueHandle_t )pvMBoxHandle,
                                     pvMBoxItem,
                                     &xHigherPriorityTaskWoken );

        if( pdPASS != xReturn )
        {
            /* Item not posted - MBox full */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Item posted successfully */
            iStatus = OSAL_ERRORS_NONE;
        }

        if( pdTRUE == xHigherPriorityTaskWoken )
        {
            /* macro used here is port specific.*/
            portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Event APIs                                                                */
/*****************************************************************************/

/**
 * @brief   Creates a new Event Flag group, and sets OS Handle by which the Event Flag group can be referenced.
 * @note    The default number of bits (or flags) implemented within an event group is 24.
 */
int iOSAL_EventFlag_Create( void** ppvEventFlagHandle, const char* pcEventFlagName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvEventFlagHandle  ) &&
        ( NULL == *ppvEventFlagHandle ) &&
        ( NULL != pcEventFlagName     ) )
    {
        *ppvEventFlagHandle = xEventGroupCreate();

        if( NULL != *ppvEventFlagHandle )
        {
            /* Add event to debug stats */
            OSAL_EVENT_STATS_LINKED_LIST *pxNewNode = ( OSAL_EVENT_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_EVENT_STATS_LINKED_LIST ) );
            if( NULL != pxNewNode )
            {
                pxNewNode->pvEvent = *ppvEventFlagHandle;
                pxNewNode->pcName = strdup( pcEventFlagName );
                pxNewNode->ulFlagWait = 0;
                pxNewNode->ulFlagSet = 0;
                pxNewNode->pcStatus = strdup( "Active" );

                pxNewNode->pxNext = pxOsStatsHandle->pxEventHead;
                pxOsStatsHandle->pxEventHead = pxNewNode;
            }

            /* Event Flag created successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
        else
        {
            /* Event Flag not created */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Deletes an Event Flag group, to which the handle refers.
 */
int iOSAL_EventFlag_Destroy( void** ppvEventFlagHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvEventFlagHandle  ) &&
        ( NULL != *ppvEventFlagHandle ) )
    {
        OSAL_EVENT_STATS_LINKED_LIST *pxCurrent = pxFindEvent( *ppvEventFlagHandle);
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        vEventGroupDelete( ( EventGroupHandle_t )*ppvEventFlagHandle );

        if( NULL != *ppvEventFlagHandle )
        {
            *ppvEventFlagHandle = NULL;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Pend task to Wait for a bit or group of bits to become set.
 */
int iOSAL_EventFlag_Pend( void* pvEventFlagHandle, uint32_t ulFlagWait, uint32_t ulTimeoutMs )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    if( NULL != pvEventFlagHandle )
    {
        TickType_t xTimeoutTicks = 0;
        BaseType_t xClearOnExit = pdTRUE;
        BaseType_t xWaitForAllBits = pdTRUE;

        if( OSAL_TIMEOUT_WAIT_FOREVER == ulTimeoutMs )
        {
            xTimeoutTicks = portMAX_DELAY;
        }
        else if( OSAL_TIMEOUT_NO_WAIT == ulTimeoutMs )
        {
            xTimeoutTicks = 0;
        }
        else
        {
            xTimeoutTicks = pdMS_TO_TICKS( ulTimeoutMs );

            if( 0 == xTimeoutTicks )
            {
                xTimeoutTicks = ONE_TICK;
            }
        }

        xEventGroupWaitBits( ( EventGroupHandle_t  )pvEventFlagHandle,
                             ( EventBits_t )ulFlagWait,
                             xClearOnExit,
                             xWaitForAllBits,
                             xTimeoutTicks );

        OSAL_EVENT_STATS_LINKED_LIST *pxCurrent = pxFindEvent( pvEventFlagHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->ulFlagWait = ulFlagWait;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   Sets or clears event flag bits, to which the handle refers.
 */
int iOSAL_EventFlag_Post( void* pvEventFlagHandle, uint32_t ulFlagSet )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvEventFlagHandle )
    {
        xEventGroupSetBits( ( EventGroupHandle_t )pvEventFlagHandle,
                            ( EventBits_t )ulFlagSet );

        OSAL_EVENT_STATS_LINKED_LIST *pxCurrent = pxFindEvent( pvEventFlagHandle );
        if( NULL != pxCurrent)
        {
            pxCurrent->ulFlagSet = ulFlagSet;
        }

        iStatus = OSAL_ERRORS_NONE;
    }

    return iStatus;
}

/**
 * @brief   A version of iOSAL_EventFlag_Post() that can be called from an ISR.
 */
int iOSAL_EventFlag_PostFromISR( void* pvEventFlagHandle, uint32_t ulFlagSet )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    if( NULL != pvEventFlagHandle )
    {
        BaseType_t xHigherPriorityTaskWoken = pdFALSE;
        BaseType_t xReturn = xEventGroupSetBitsFromISR( ( EventGroupHandle_t )pvEventFlagHandle,
                                                        ( EventBits_t )ulFlagSet,
                                                        &xHigherPriorityTaskWoken );

        if( pdPASS != xReturn )
        {
            /* Event Flags not set correctly */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Item posted successfully */
            iStatus = OSAL_ERRORS_NONE;
        }

        if( pdTRUE == xHigherPriorityTaskWoken )
        {
            /* macro used here is port specific.*/
            portYIELD_FROM_ISR( xHigherPriorityTaskWoken );
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Timer APIs                                                                */
/*****************************************************************************/

/**
 * @brief   Creates a new software timer instance, and sets OS Handle by which the Timer can be referenced.
 */
int iOSAL_Timer_Create( void** ppvTimerHandle,
                        OSAL_TIMER_CONFIG xTimerConfig,
                        void ( *pvTimerCallback )( void* pvTimerHandle ),
                        const char* pcTimerName )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvTimerHandle  ) &&
        ( NULL == *ppvTimerHandle ) &&
        ( MAX_OSAL_TIMER_CONFIG > xTimerConfig ) &&
        ( NULL != pvTimerCallback ) &&
        ( NULL != pcTimerName ) )
    {
        UBaseType_t xAutoReload = pdFALSE; /* one shot */
        TickType_t xTimerPeriodTicks = pdMS_TO_TICKS( DEFAULT_TIMER_PERIOD_MS );

        if( 0 == xTimerPeriodTicks )
        {
            xTimerPeriodTicks = ONE_TICK;
        }

        if( OSAL_TIMER_CONFIG_PERIODIC == xTimerConfig )
        {
            xAutoReload = pdTRUE; /* periodic */
        }

        *ppvTimerHandle = xTimerCreate( pcTimerName,
                                        xTimerPeriodTicks,
                                        xAutoReload,
                                        NULL,
                                        ( TimerCallbackFunction_t )pvTimerCallback );

        if( NULL != *ppvTimerHandle )
        {
            /* Add timer to debug stats */
            OSAL_TIMER_STATS_LINKED_LIST *pxNewNode = ( OSAL_TIMER_STATS_LINKED_LIST* ) pvOSAL_MemAlloc( sizeof( OSAL_TIMER_STATS_LINKED_LIST ) );
            if( NULL != pxNewNode )
            {
                pxNewNode->pvTimer = *ppvTimerHandle;
                pxNewNode->pcName = strdup( pcTimerName );
                pxNewNode->iRunCount = 0;
                pxNewNode->pcType = strdup( OSAL_TIMER_CONFIG_PERIODIC == xTimerConfig ? "Periodic" : "One-shot" );
                pxNewNode->pcStatus = strdup( "Active" );

                pxNewNode->pxNext = pxOsStatsHandle->pxTimerHead;
                pxOsStatsHandle->pxTimerHead = pxNewNode;
            }

            /* Timer created successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
        else
        {
            /* Timer not created */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
    }

    return iStatus;
}

/**
 * @brief   Deletes a Timer, to which the handle refers.
 */
int iOSAL_Timer_Destroy( void** ppvTimerHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != ppvTimerHandle ) &&
        ( NULL != *ppvTimerHandle ) )
    {
        OSAL_TIMER_STATS_LINKED_LIST *pxCurrent = pxFindTimer( *ppvTimerHandle);
        if( NULL != pxCurrent)
        {
            pxCurrent->pcStatus = strdup( "Deleted" );
        }

        TickType_t xBlockTime = pdMS_TO_TICKS( DEFAULT_TIMER_BLOCK_TIME_MS );

        if( pdPASS != xTimerDelete( *ppvTimerHandle,
                                    xBlockTime ) )
        {
            /* Timer not deleted */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Timer deleted */
            if( NULL != *ppvTimerHandle )
            {
                *ppvTimerHandle = NULL;
            }

            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Starts a Timer, to which the handle refers.
 */
int iOSAL_Timer_Start( void* pvTimerHandle, uint32_t ulDurationMs )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != pvTimerHandle ) &&
        ( 0 < ulDurationMs ) )
    {
        TickType_t xBlockTime = pdMS_TO_TICKS( DEFAULT_TIMER_BLOCK_TIME_MS );
        TickType_t xTimerPeriodTicks = pdMS_TO_TICKS( ulDurationMs );

        if( 0 == xTimerPeriodTicks )
        {
            xTimerPeriodTicks = ONE_TICK;
        }

        /* reset timer period */
        if( pdPASS != xTimerChangePeriod( ( TimerHandle_t )pvTimerHandle,
                                          xTimerPeriodTicks,
                                          xBlockTime ) )
        {
            /* Timer period not set */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Timer period set, start timer */
            if( pdPASS != xTimerStart( ( TimerHandle_t )pvTimerHandle,
                                       xBlockTime ) )
            {
                /* Timer not started */
                iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
            }
            else
            {
                OSAL_TIMER_STATS_LINKED_LIST *pxCurrent = pxFindTimer( pvTimerHandle );
                if( NULL != pxCurrent)
                {
                    pxCurrent->ulDurationMs = ulDurationMs;
                    pxCurrent->iRunCount++;
                }

                /* Timer started */
                iStatus = OSAL_ERRORS_NONE;
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Stops a Timer, to which the handle refers.
 */
int iOSAL_Timer_Stop( void* pvTimerHandle )
{
    int iStatus = OSAL_ERRORS_INVALID_HANDLE;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvTimerHandle )
    {
        TickType_t xBlockTime = pdMS_TO_TICKS( DEFAULT_TIMER_BLOCK_TIME_MS );

        if( pdPASS != xTimerStop( ( TimerHandle_t )pvTimerHandle,
                                  xBlockTime ) )
        {
            /* Timer not stopped */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Timer stopped */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Re-Starts a Timer, to which the handle refers.
 */
int iOSAL_Timer_Reset( void* pvTimerHandle, uint32_t ulDurationMs )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( ( NULL != pvTimerHandle ) &&
        ( 0 < ulDurationMs ) )
    {
        TickType_t xBlockTime = pdMS_TO_TICKS( DEFAULT_TIMER_BLOCK_TIME_MS );
        TickType_t xTimerPeriodTicks = pdMS_TO_TICKS( ulDurationMs );

        if( 0 == xTimerPeriodTicks )
        {
            xTimerPeriodTicks = ONE_TICK;
        }

        /* reset timer period */
        if( pdPASS != xTimerChangePeriod( ( TimerHandle_t )pvTimerHandle,
                                          xTimerPeriodTicks,
                                          xBlockTime ) )
        {
            /* Timer period not set */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Timer period set, restart timer */
            if( pdPASS != xTimerReset( ( TimerHandle_t )pvTimerHandle,
                                       xBlockTime ) )
            {
                /* Timer not started */
                iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
            }
            else
            {
                OSAL_TIMER_STATS_LINKED_LIST *pxCurrent = pxFindTimer( pvTimerHandle );
                if( NULL != pxCurrent)
                {
                    pxCurrent->ulDurationMs = ulDurationMs;
                    pxCurrent->iRunCount++;
                }

                /* Timer started */
                iStatus = OSAL_ERRORS_NONE;
            }
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Interrupt APIs                                                            */
/*****************************************************************************/

/**
 * @brief   Sets up interrupt handler callback with appropriate interrupt ID
 */
int iOSAL_Interrupt_Setup( uint8_t ucInterruptID,
                           void    ( *pvInterruptHandler )( void* pvCallBackRef ),
                           void*   pvCallBackRef )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    if( NULL != pvInterruptHandler )
    {
        if( pdPASS != xPortInstallInterruptHandler( ucInterruptID, ( XInterruptHandler )pvInterruptHandler, pvCallBackRef ) )
        {
            /* Interrupts not setup */
            iStatus = OSAL_ERRORS_OS_IMPLEMENTATION;
        }
        else
        {
            /* Interrupts setup successfully */
            iStatus = OSAL_ERRORS_NONE;
        }
    }

    return iStatus;
}

/**
 * @brief   Enable OSAL interrupts
 */
int iOSAL_Interrupt_Enable( uint8_t ucInterruptID )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    vPortEnableInterrupt( ucInterruptID );
    iStatus = OSAL_ERRORS_NONE;

    return iStatus;
}

/**
 * @brief   Disable OSAL interrupts
 */
int iOSAL_Interrupt_Disable( uint8_t ucInterruptID )
{
    int iStatus = OSAL_ERRORS_PARAMS;

    RETURN_IF_OS_NOT_STARTED;

    vPortDisableInterrupt( ucInterruptID );
    iStatus = OSAL_ERRORS_NONE;

    return iStatus;
}


/*****************************************************************************/
/* Thread safe APIs                                                          */
/*****************************************************************************/

/**
 * @brief   Mark the start of critical code region.
 */
void vOSAL_EnterCritical( void )
{
    /* FreeRTOS Macro */
    taskENTER_CRITICAL();
}

/**
 * @brief   Mark the end of critical code region.
 */
void vOSAL_ExitCritical( void )
{
    /* FreeRTOS Macro */
    taskEXIT_CRITICAL();
}

/**
 * @brief   OSAL wrapper for task/thread safe memory allocation.
 */
void* pvOSAL_MemAlloc( uint16_t xSize )
{
    void* pvMemory = NULL;

    if( 0 < xSize )
    {
        if( TRUE == iOsStarted )
        {
            /* thread safe */
            pvMemory = pvPortMalloc( ( size_t )xSize );
        }
        else
        {
            /* note: Not thread safe */
            pvMemory = malloc( ( size_t )xSize );
        }

        pxOsStatsHandle->iMemAllocCallCount++;
    }

    return pvMemory;
}

/**
 * @brief   OSAL wrapper for task/thread safe memory set.
 */
void* pvOSAL_MemSet( void* pvDestination, int iValue, uint16_t usSize )
{
    void* pvSetMemory = NULL;

    if( NULL != pvDestination )
    {
        if( TRUE == iOsStarted )
        {
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;

            /* take semaphore */
            if( pdPASS == xSemaphoreTakeFromISR( ( SemaphoreHandle_t ) pvMemSetSemHandle, &xHigherPriorityTaskWoken ) )
            {
                /* semaphore taken successfully, set memory */
                pvSetMemory = memset( pvDestination, iValue, ( size_t )usSize );

                /* release semaphore */
                xSemaphoreGiveFromISR( ( SemaphoreHandle_t ) pvMemSetSemHandle, &xHigherPriorityTaskWoken );
            }
        }
        else
        {
            /* set memory, note: Not thread safe */
            pvSetMemory = memset( pvDestination, iValue, ( size_t )usSize );
        }
    }

    return pvSetMemory;
}

/**
 * @brief   OSAL wrapper for task/thread safe memory copy.
 */
void* pvOSAL_MemCpy( void* pvDestination, const void* pvSource, uint16_t usSize )
{
    void* pvSetMemory = NULL;

    if( ( NULL != pvDestination ) &&
        ( NULL != pvSource ) )
    {
        if( TRUE == iOsStarted )
        {
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;

            /* take semaphore */
            if( pdPASS == xSemaphoreTakeFromISR( ( SemaphoreHandle_t ) pvMemCpySemHandle, &xHigherPriorityTaskWoken ) )
            {
                /* semaphore taken successfully, copy memory */
                pvSetMemory = memcpy( pvDestination, pvSource, ( size_t )usSize );

                /* release semaphore */
                xSemaphoreGiveFromISR( ( SemaphoreHandle_t ) pvMemCpySemHandle, &xHigherPriorityTaskWoken );
            }
        }
        else
        {
            /* copy memory, note: Not thread safe */
            pvSetMemory = memcpy( pvDestination, pvSource, ( size_t )usSize );
        }
    }

    return pvSetMemory;
}

/**
 * @brief   OSAL wrapper for task/thread safe memory movement.
 */
void vOSAL_MemMove( void *pvDestination, void *pvSource, uint16_t usPayload_size )
{
    if( ( NULL != pvDestination ) &&
        ( NULL != pvSource ) )
    {
        if( TRUE == iOsStarted )
        {
            /* thread safe */
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;
            /* take semaphore */
            if( pdPASS == xSemaphoreTakeFromISR( ( SemaphoreHandle_t ) pvMemMoveSemHandle, &xHigherPriorityTaskWoken ) )
            {
                /* semaphore taken successfully, move memory */
                memmove( pvDestination,
                         pvSource,
                         ( size_t )usPayload_size );
                /* release semaphore */
                xSemaphoreGiveFromISR( ( SemaphoreHandle_t ) pvMemMoveSemHandle, &xHigherPriorityTaskWoken );
            }
        }
        else
        {
            /* note: Not thread safe */
            memmove( pvDestination,
                     pvSource,
                     ( size_t )usPayload_size );
        }
    }
}

/**
 * @brief   OSAL wrapper for task/thread safe memory deallocation.
 */
void vOSAL_MemFree( void** ppv )
{
    if( ( NULL != ppv ) &&
        ( NULL != *ppv ) )
    {
        if( TRUE == iOsStarted )
        {
            /* thread safe */
            vPortFree( *ppv );

            if( NULL != *ppv )
            {
                *ppv = NULL;
            }
        }
        else
        {
            /* note: Not thread safe */
            free( *ppv );

            if( NULL != *ppv )
            {
                *ppv = NULL;
            }
        }

        pxOsStatsHandle->iMemFreeCallCount++;
    }
}

/**
 * @brief   OSAL wrapper for task/thread safe prints.
 */
void vOSAL_Printf( const char* pcFormat, ... )
{
    if( ( NULL != pcFormat ) &&
        ( PRINT_BUFFER_SIZE >= strlen( pcFormat ) ) )
    {
        char buffer[ PRINT_BUFFER_SIZE ] = { 0 };
        va_list args = { 0 };

        va_start( args, pcFormat );
        vsnprintf( buffer, PRINT_BUFFER_SIZE, pcFormat, args );

        if( TRUE == iOsStarted )
        {
            /* take Mutex */
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pvPrintfMutexHandle, OSAL_TIMEOUT_TASK_WAIT_MS ) )
            {
                /* Mutex taken successfully, print string */
                xil_printf( "%s", buffer );

                /* release Mutex */
                iOSAL_Mutex_Release( pvPrintfMutexHandle );
            }
        }
        else
        {
            /* print string, note: Not thread safe */
            xil_printf( "%s", buffer );
        }

        va_end( args );
    }
}

/**
 * @brief   OSAL wrapper for task/thread safe char reading.
 */
char cOSAL_GetChar( void )
{
    char cInput = '\0';

    if( TRUE == iOsStarted )
    {
        /* take Mutex */
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pvGetCharMutexHandle, OSAL_TIMEOUT_TASK_WAIT_MS ) )
        {
            /* Mutex taken successfully, read character */
            cInput = inbyte();

            /* release Mutex */
            iOSAL_Mutex_Release( pvGetCharMutexHandle );
        }
    }
    else
    {
        /* read character, note: Not thread safe */
        cInput = inbyte();
    }

    return cInput;
}

/**
 * @brief   OSAL wrapper for task/thread safe string copy.
 */
char* pcOSAL_StrNCpy( char *pcDestination, const char *pcSource, uint16_t usSize )
{
    char *pcSetString = NULL;

    if( ( NULL != pcDestination ) && 
        ( NULL != pcSource ) && 
        ( 0 < usSize ) )
    {
        if( TRUE == iOsStarted )
        {
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;

            /* take semaphore */
            if ( pdPASS == xSemaphoreTakeFromISR( ( SemaphoreHandle_t ) pvStrNCpySemHandle, &xHigherPriorityTaskWoken ) )
            {
                /* semaphore taken successfully, copy string */
                pcSetString = strncpy( pcDestination, pcSource, ( size_t )usSize );

                /* release semaphore */
                xSemaphoreGiveFromISR( ( SemaphoreHandle_t ) pvStrNCpySemHandle, &xHigherPriorityTaskWoken );
            }
        }
        else
        {
            /* copy string, note: Not thread safe */
            pcSetString = strncpy( pcDestination, pcSource, ( size_t )usSize );
        }
    }

    return pcSetString;
}

/**
 * @brief   OSAL wrapper for task/thread safe memory compare.
 */
int iOSAL_MemCmp( const void *pvMemoryOne, const void *pvMemoryTwo, uint16_t usSize )
{
    int iStatus = ERROR;

    if( ( NULL != pvMemoryOne ) && 
        ( NULL != pvMemoryTwo ) &&
        ( 0 < usSize ) )
    {
        if( TRUE == iOsStarted )
        {
            BaseType_t xHigherPriorityTaskWoken = pdFALSE;

            /* take semaphore */
            if ( pdPASS == xSemaphoreTakeFromISR( ( SemaphoreHandle_t ) pvMemCmpSemHandle, &xHigherPriorityTaskWoken ) )
            {
                /* semaphore taken successfully, compare memory */
                iStatus = memcmp( pvMemoryOne, pvMemoryTwo, ( size_t )usSize );

                /* release semaphore */
                xSemaphoreGiveFromISR( ( SemaphoreHandle_t ) pvMemCmpSemHandle, &xHigherPriorityTaskWoken );
            }
        }
        else
        {
            /* compare memory, note: Not thread safe */
            iStatus = memcmp( pvMemoryOne, pvMemoryTwo, ( size_t )usSize );
        }
    }

    return iStatus;
}


/*****************************************************************************/
/* Local function implementation                                             */
/*****************************************************************************/

/**
 * @brief   Looks for a free block in the task shared memory pool.
 */
static OSAL_TASK_MEMORY* pxAllocateTaskMemory( void )
{
    int i = 0;
    OSAL_TASK_MEMORY* pxMemory = NULL;

    for( i = 0; i < OSAL_MAX_TASKS; i++ )
    {
        if( MEM_UNUSED == xTaskMemoryUsed[ i ] )
        {
            xTaskMemoryUsed[ i ] = MEM_USED;
            pxMemory = &xTaskMemoryPool[ i ];
            break; 
        }
    }

    return pxMemory; 
}

/**
 * @brief   Frees a block of the task shared memory pool.
 */
static void vDeallocateTaskMemory( OSAL_TASK_MEMORY* pxMemory )
{
    int iIndex = 0;
    iIndex = pxMemory - xTaskMemoryPool;

    if( ( 0 <= iIndex ) &&
        ( iIndex < OSAL_MAX_TASKS ) )
    {
        /* check if memory is not already free */
        if( MEM_UNUSED != xTaskMemoryUsed[ iIndex ] )
        {
            xTaskMemoryUsed[ iIndex ] = MEM_UNUSED;
        }
    }
}


/*****************************************************************************/
/* Debug stats functions                                                     */
/*****************************************************************************/

/**
 * @brief   Prints All debug stats.
 */
void vOSAL_PrintAllStats( OSAL_STATS_VERBOSITY eVerbosity, OSAL_STATS_TYPE eStatType )
{
    switch ( eStatType )
    {
        case OSAL_STATS_TYPE_OS:
            vPrint_OS_Stats();
            break;

        case OSAL_STATS_TYPE_TASK:
            vPrint_Task_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_MUTEX:
            vPrint_Mutex_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_SEM:
            vPrint_Sem_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_MAILBOX:
            vPrint_Mailbox_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_EVENT:
            vPrint_Event_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_TIMER:
            vPrint_Timer_Stats( eVerbosity );
            break;

        case OSAL_STATS_TYPE_MEMORY:
            vPrint_Memory_Stats();
            break;

        default:
            vPrint_OS_Stats();
            vPrint_Task_Stats( eVerbosity );
            vPrint_Sem_Stats( eVerbosity );
            vPrint_Mutex_Stats( eVerbosity );
            vPrint_Mailbox_Stats( eVerbosity );
            vPrint_Event_Stats( eVerbosity );
            vPrint_Timer_Stats( eVerbosity );
            vPrint_Memory_Stats();
            break;
    }
}

/**
 * @brief   Clears debug stats and frees associated memory.
 */
void vOSAL_ClearAllStats( void )
{
    if( NULL != pxOsStatsHandle )
    {
        /* strdup uses malloc under the hood - vOSAL_MemFree can't be used */

        OSAL_TASK_STATS_LINKED_LIST* pxCurrentTask = pxOsStatsHandle->pxTaskHead;

        while( NULL != pxCurrentTask )
        {
            OSAL_TASK_STATS_LINKED_LIST* pxTemp = pxCurrentTask;
            pxCurrentTask = pxCurrentTask->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** ) &pxTemp );
        }

        pxOsStatsHandle->pxTaskHead = NULL;

        OSAL_SEM_STATS_LINKED_LIST* pxCurrentSem = pxOsStatsHandle->pxSemHead;

        while( NULL != pxCurrentSem )
        {
            OSAL_SEM_STATS_LINKED_LIST* pxTemp = pxCurrentSem;
            pxCurrentSem = pxCurrentSem->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** )&pxTemp );
        }
        
        pxOsStatsHandle->pxSemHead = NULL;

        OSAL_MUTEX_STATS_LINKED_LIST* pxCurrentMutex = pxOsStatsHandle->pxMutexHead;

        while( NULL != pxCurrentMutex )
        {
            OSAL_MUTEX_STATS_LINKED_LIST* pxTemp = pxCurrentMutex;
            pxCurrentMutex = pxCurrentMutex->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** )&pxTemp );
        }

        pxOsStatsHandle->pxMutexHead = NULL;

        OSAL_MBOX_STATS_LINKED_LIST* pxCurrentMailbox = pxOsStatsHandle->pxMailboxHead;

        while( NULL != pxCurrentMailbox )
        {
            OSAL_MBOX_STATS_LINKED_LIST* pxTemp = pxCurrentMailbox;
            pxCurrentMailbox = pxCurrentMailbox->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** )&pxTemp );
        }

        pxOsStatsHandle->pxMailboxHead = NULL;

        OSAL_EVENT_STATS_LINKED_LIST* pxCurrentEvent = pxOsStatsHandle->pxEventHead;

        while( NULL != pxCurrentEvent )
        {
            OSAL_EVENT_STATS_LINKED_LIST* pxTemp = pxCurrentEvent;
            pxCurrentEvent = pxCurrentEvent->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** )&pxTemp );
        }

        pxOsStatsHandle->pxEventHead = NULL;

        OSAL_TIMER_STATS_LINKED_LIST* pxCurrentTimer = pxOsStatsHandle->pxTimerHead;

        while( NULL != pxCurrentTimer )
        {
            OSAL_TIMER_STATS_LINKED_LIST* pxTemp = pxCurrentTimer;
            pxCurrentTimer = pxCurrentTimer->pxNext;

            free( pxTemp->pcName );
            free( pxTemp->pcType );
            free( pxTemp->pcStatus );
            vOSAL_MemFree( ( void** )&pxTemp );
        }

        pxOsStatsHandle->pxTimerHead = NULL;
    }
}

/**
 * @brief   Prints debug stats header.
 */
static void vPrint_Header( const char* pcType )
{
    if( NULL != pcType )
    {
        vOSAL_Printf( "\r\n%s Statistics:\r\n", pcType );
        vOSAL_Printf( LINE_SEPARATOR );
    }
}

/**
 * @brief   Prints debug stats footer.
 */
static void vPrint_Footer( int iCount, const char* pcType )
{
    if( NULL != pcType )
    {
        vOSAL_Printf( LINE_SEPARATOR );
        vOSAL_Printf( "Total %ss created: %d\r\n", pcType, iCount );
        vOSAL_Printf( LINE_SEPARATOR );
    }
}

/**
 * @brief   Prints OS related debug stats.
 */
static void vPrint_OS_Stats( void )
{
    size_t xTotalHeapSize = 0;
    size_t xFreeHeapSize = 0;
    size_t xHeapWaterMark = 0;

    xTotalHeapSize = configTOTAL_HEAP_SIZE;
    xFreeHeapSize = xPortGetFreeHeapSize();
    xHeapWaterMark = xPortGetMinimumEverFreeHeapSize();

    vOSAL_Printf( "\r\nOS Statistics:\r\n" );
    vOSAL_Printf( LINE_SEPARATOR );
    vOSAL_Printf( "%-20s %-20s %-20s \r\n", "Total Heap Size", "Free Heap Size", "Heap Water Mark" );
    vOSAL_Printf( LINE_SEPARATOR );
    vOSAL_Printf( "%-20zu %-20zu %-20zu \r\n", xTotalHeapSize , xFreeHeapSize, xHeapWaterMark );
    vOSAL_Printf( LINE_SEPARATOR );
}

/**
 * @brief   Prints Task related debug stats.
 */
static void vPrint_Task_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_TASK_STATS_LINKED_LIST* pxCurrentTask = pxOsStatsHandle->pxTaskHead;
    int iTaskCount = 0;

    vCalculateStackWatermark();

    /* For this function to run, Extra debug must be enabled in the BSP */
#ifdef FREERTOS_DEBUG
    vCalculateCpuUsage();
#endif

    vPrint_Header( "Task" );

    switch( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-20s %-20s %-15s\r\n", "Task Name", "Status", "Task Priority", "Stack Size (kb)", "Peak Usage (kb)", "CPU Usage" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentTask )
            {
                if( 0 == pxCurrentTask->ulCpuUsagePercentage )
                {
                    if( OK == strcmp( pxCurrentTask->pcStatus, "Active" ) )
                    {
                        vOSAL_Printf( "%-30s %-15s %-15lu %-20u %-20u <1%%\r\n",
                                      pxCurrentTask->pcName,
                                      pxCurrentTask->pcStatus,
                                      pxCurrentTask->ulTaskPriority,
                                      pxCurrentTask->usTaskStackSize,
                                      pxCurrentTask->usTaskStackWaterMark );
                        iTaskCount++;
                    }
                }
                else
                {
                    if( OK == strcmp( pxCurrentTask->pcStatus, "Active" ) )
                    {
                        vOSAL_Printf( "%-30s %-15s %-15lu %-20u %-20u %lu%%\r\n",
                                      pxCurrentTask->pcName,
                                      pxCurrentTask->pcStatus,
                                      pxCurrentTask->usTaskStackSize,
                                      pxCurrentTask->ulTaskPriority,
                                      pxCurrentTask->usTaskStackWaterMark,
                                      pxCurrentTask->ulCpuUsagePercentage );
                        iTaskCount++;
                    }
                }

                pxCurrentTask = pxCurrentTask->pxNext;
            }

            vPrint_Footer(iTaskCount, "Task");
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-20s %-20s %-15s\r\n", "Task Name", "Status", "Task Priority", "Stack Size (kb)", "Peak Usage (kb)", "CPU Usage" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentTask )
            {
                if( 0 == pxCurrentTask->ulCpuUsagePercentage )
                {
                    vOSAL_Printf( "%-30s %-15s %-15lu %-20u %-20u <1%%\r\n",
                                    pxCurrentTask->pcName,
                                    pxCurrentTask->pcStatus,
                                    pxCurrentTask->ulTaskPriority,
                                    pxCurrentTask->usTaskStackSize,
                                    pxCurrentTask->usTaskStackWaterMark );
                    iTaskCount++;
                }
                else
                {
                    vOSAL_Printf( "%-30s %-15s %-15lu %-20u %-20u %lu%%\r\n",
                                  pxCurrentTask->pcName,
                                  pxCurrentTask->pcStatus,
                                  pxCurrentTask->usTaskStackSize,
                                  pxCurrentTask->ulTaskPriority,
                                  pxCurrentTask->usTaskStackWaterMark,
                                  pxCurrentTask->ulCpuUsagePercentage );
                    iTaskCount++;
                }

                pxCurrentTask = pxCurrentTask->pxNext;
            }

            vPrint_Footer( iTaskCount, "Task" );
            break;

        default:
            while( NULL != pxCurrentTask )
            {
                pxCurrentTask = pxCurrentTask->pxNext;
                iTaskCount++;
            }

            vPrint_Footer( iTaskCount, "Task" );
            break;
    }
}

/**
 * @brief   Prints Semaphore related debug stats.
 */
static void vPrint_Sem_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_SEM_STATS_LINKED_LIST* pxCurrentSem = pxOsStatsHandle->pxSemHead;
    int iSemCount = 0;

    vPrint_Header( "Semaphore" );

    switch ( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Semaphore Name", "Status", "Post Count", "Pend Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentSem )
            {
                if( OK == strcmp( pxCurrentSem->pcStatus, "Active" ) )
                {
                    vOSAL_Printf( "%-30s %-15s %-15d %-15d \r\n", pxCurrentSem->pcName, pxCurrentSem->pcStatus, pxCurrentSem->iPostCount, pxCurrentSem->iPendCount );
                    iSemCount++;
                }
                pxCurrentSem = pxCurrentSem->pxNext;
            }

            vPrint_Footer( iSemCount, "Semaphore" );
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Semaphore Name", "Status", "Post Count", "Pend Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentSem )
            {
                vOSAL_Printf( "%-30s %-15s %-15d %-15d \r\n", pxCurrentSem->pcName, pxCurrentSem->pcStatus, pxCurrentSem->iPostCount, pxCurrentSem->iPendCount );
                pxCurrentSem = pxCurrentSem->pxNext;
                iSemCount++;
            }

            vPrint_Footer( iSemCount, "Semaphore" );
            break;

        default:
            while( NULL != pxCurrentSem )
            {
                iSemCount++;
                pxCurrentSem = pxCurrentSem->pxNext;
            }

            vPrint_Footer( iSemCount, "Semaphore" );
            break;
    }
}

/**
 * @brief   Prints Mutex related debug stats.
 */
static void vPrint_Mutex_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_MUTEX_STATS_LINKED_LIST* pxCurrentMutex = pxOsStatsHandle->pxMutexHead;
    int iMutexCount = 0;

    vPrint_Header( "Mutex" );

    switch ( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Mutex Name", "Status", "Take Count", "Release Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentMutex )
            {
                if( OK == strcmp( pxCurrentMutex->pcStatus, "Active" ) )
                {
                    vOSAL_Printf( "%-30s %-15s %-15d %-15d \r\n", pxCurrentMutex->pcName, pxCurrentMutex->pcStatus, pxCurrentMutex->iTakeCount, pxCurrentMutex->iReleaseCount );
                    iMutexCount++;
                }
                pxCurrentMutex = pxCurrentMutex->pxNext;
            }

            vPrint_Footer( iMutexCount, "Mutex" );
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Mutex Name", "Status", "Take Count", "Release Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentMutex )
            {
                vOSAL_Printf( "%-30s %-15s %-15d %-15d \r\n", pxCurrentMutex->pcName, pxCurrentMutex->pcStatus, pxCurrentMutex->iTakeCount, pxCurrentMutex->iReleaseCount );
                pxCurrentMutex = pxCurrentMutex->pxNext;
                iMutexCount++;
            }

            vPrint_Footer( iMutexCount, "Mutex" );
            break;

        default:
            while( NULL != pxCurrentMutex )
            {
                pxCurrentMutex = pxCurrentMutex->pxNext;
                iMutexCount++;
            }

            vPrint_Footer( iMutexCount, "Mutex" );
            break;
    }
}

/**
 * @brief   Prints Mailbox related debug stats.
 */
static void vPrint_Mailbox_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_MBOX_STATS_LINKED_LIST* pxCurrentMailbox = pxOsStatsHandle->pxMailboxHead;
    int iMailboxCount = 0;

    vPrint_Header( "Mailbox" );

    switch ( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s %-15s %-15s %-15s\r\n", "Mailbox Name", "Status", "MBox Length", "Item Size", "Rx Count", "Tx Count", "Item Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentMailbox )
            {
                if( OK == strcmp( pxCurrentMailbox->pcStatus, "Active" ) )
                {
                    vOSAL_Printf( "%-30s %-15s %-15lu %-15lu %-15d %-15d %-15d\r\n", pxCurrentMailbox->pcName, pxCurrentMailbox->pcStatus,  pxCurrentMailbox->ulMBoxLength, pxCurrentMailbox->ulItemSize, pxCurrentMailbox->iRxCount, pxCurrentMailbox->iTxCount, pxCurrentMailbox->iItemCount );
                    iMailboxCount++;
                }
                pxCurrentMailbox = pxCurrentMailbox->pxNext;
            }

            vPrint_Footer( iMailboxCount, "Mailbox" );
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s %-15s %-15s %-15s\r\n", "Mailbox Name", "Status", "MBox Length", "Item Size", "Rx Count", "Tx Count", "Item Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentMailbox )
            {
                vOSAL_Printf( "%-30s %-15s %-15lu %-15lu %-15d %-15d %-15d\r\n", pxCurrentMailbox->pcName, pxCurrentMailbox->pcStatus,  pxCurrentMailbox->ulMBoxLength, pxCurrentMailbox->ulItemSize, pxCurrentMailbox->iRxCount, pxCurrentMailbox->iTxCount, pxCurrentMailbox->iItemCount );
                pxCurrentMailbox = pxCurrentMailbox->pxNext;
                iMailboxCount++;
            }

            vPrint_Footer( iMailboxCount, "Mailbox" );
            break;

        default:
            while( NULL != pxCurrentMailbox )
            {
                pxCurrentMailbox = pxCurrentMailbox->pxNext;
                iMailboxCount++;
            }

            vPrint_Footer( iMailboxCount, "Mailbox" );
            break;
    }
}

/**
 * @brief   Prints Event related debug stats.
 */
static void vPrint_Event_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_EVENT_STATS_LINKED_LIST* pxCurrentEvent = pxOsStatsHandle->pxEventHead;
    int iEventCount = 0;

    vPrint_Header( "Event" );

    switch ( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Event Flag Name", "Status", "Flag Wait", "Flag Set" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentEvent )
            {
                if( OK == strcmp( pxCurrentEvent->pcStatus, "Active" ) )
                {
                    vOSAL_Printf( "%-30s %-15s %-15lu %-15lu \r\n", pxCurrentEvent->pcName, pxCurrentEvent->pcStatus, pxCurrentEvent->ulFlagWait, pxCurrentEvent->ulFlagSet );
                    iEventCount++;
                }
                pxCurrentEvent = pxCurrentEvent->pxNext;
            }

            vPrint_Footer( iEventCount, "Event" );
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s\r\n", "Event Flag Name", "Status", "Flag Wait", "Flag Set" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentEvent )
            {
                vOSAL_Printf( "%-30s %-15s %-15lu %-15lu \r\n", pxCurrentEvent->pcName, pxCurrentEvent->pcStatus, pxCurrentEvent->ulFlagWait, pxCurrentEvent->ulFlagSet );
                pxCurrentEvent = pxCurrentEvent->pxNext;
                iEventCount++;
            }

            vPrint_Footer( iEventCount, "Event" );
            break;

        default:
            while( NULL != pxCurrentEvent )
            {
                pxCurrentEvent = pxCurrentEvent->pxNext;
                iEventCount++;
            }

            vPrint_Footer( iEventCount, "Event" );
            break;
    }
}

/**
 * @brief   Prints Timer related debug stats.
 */
static void vPrint_Timer_Stats( OSAL_STATS_VERBOSITY eVerbosity )
{
    OSAL_TIMER_STATS_LINKED_LIST* pxCurrentTimer = pxOsStatsHandle->pxTimerHead;
    int iTimerCount = 0;

    vPrint_Header( "Timer" );

    switch ( eVerbosity )
    {
        case OSAL_STATS_VERBOSITY_ACTIVE_ONLY:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s %-15s\r\n", "Timer Name", "Status", "Type", "Duration (ms)", "Run Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentTimer )
            {
                if( OK == strcmp( pxCurrentTimer->pcStatus, "Active" ) )
                {
                    vOSAL_Printf( "%-30s %-15s %-15s %-15lu %-15d \r\n", pxCurrentTimer->pcName, pxCurrentTimer->pcStatus, pxCurrentTimer->pcType, pxCurrentTimer->ulDurationMs, pxCurrentTimer->iRunCount );
                    iTimerCount++;
                }
                pxCurrentTimer = pxCurrentTimer->pxNext;
            }

            vPrint_Footer( iTimerCount, "Timer" );
            break;

        case OSAL_STATS_VERBOSITY_FULL:
            vOSAL_Printf( "%-30s %-15s %-15s %-15s %-15s\r\n", "Timer Name", "Status", "Type", "Duration (ms)", "Run Count" );
            vOSAL_Printf( LINE_SEPARATOR );

            while( NULL != pxCurrentTimer )
            {
                vOSAL_Printf( "%-30s %-15s %-15s %-15lu %-15d \r\n", pxCurrentTimer->pcName, pxCurrentTimer->pcStatus, pxCurrentTimer->pcType, pxCurrentTimer->ulDurationMs, pxCurrentTimer->iRunCount );
                pxCurrentTimer = pxCurrentTimer->pxNext;
                iTimerCount++;
            }

            vPrint_Footer( iTimerCount, "Timer" );
            break;

        default:
            while( NULL != pxCurrentTimer )
            {
                pxCurrentTimer = pxCurrentTimer->pxNext;
                iTimerCount++;
            }

            vPrint_Footer( iTimerCount, "Timer" );
            break;
    }
}

/**
 * @brief   Prints Memory related debug stats.
 */
static void vPrint_Memory_Stats( void )
{
    vPrint_Header( "Memory" );
    vOSAL_Printf( "Total Active Memory Locations: %d\r\n", ( pxOsStatsHandle->iMemAllocCallCount - pxOsStatsHandle->iMemFreeCallCount ) );
    vOSAL_Printf( "Total MemAlloc calls: %d\r\n", pxOsStatsHandle->iMemAllocCallCount );
    vOSAL_Printf( "Total MemFree calls: %d\r\n", pxOsStatsHandle->iMemFreeCallCount );
    vOSAL_Printf( LINE_SEPARATOR );
}

/**
 * @brief Searches for node in the task linked list that matches the handle.
 */
static OSAL_TASK_STATS_LINKED_LIST* pxFindTask( void* pvTaskHandle )
{
    OSAL_TASK_STATS_LINKED_LIST *pxTaskNode = NULL;

    if( NULL != pvTaskHandle )
    {
        OSAL_TASK_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxTaskHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvTask != pvTaskHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxTaskNode = pxCurrentNode;
        }
    }

    return pxTaskNode;
}

/**
 * @brief Searches for node in the sem linked list that matches the handle.
 */
static OSAL_SEM_STATS_LINKED_LIST* pxFindSem( void* pvSemHandle )
{
    OSAL_SEM_STATS_LINKED_LIST *pxSemNode = NULL;

    if( NULL != pvSemHandle )
    {
        OSAL_SEM_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxSemHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvSem != pvSemHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxSemNode = pxCurrentNode;
        }
    }

    return pxSemNode;
}

/**
 * @brief Searches for node in the mutex linked list that matches the handle.
 */
static OSAL_MUTEX_STATS_LINKED_LIST* pxFindMutex( void* pvMutexHandle )
{
    OSAL_MUTEX_STATS_LINKED_LIST *pxMutexNode = NULL;

    if( NULL != pvMutexHandle )
    {
        OSAL_MUTEX_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxMutexHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvMutex != pvMutexHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxMutexNode = pxCurrentNode;
        }
    }

    return pxMutexNode;
}

/**
 * @brief Searches for node in the mailbox linked list that matches the handle.
 */
static OSAL_MBOX_STATS_LINKED_LIST* pxFindMailbox( void* pvMailboxHandle )
{
    OSAL_MBOX_STATS_LINKED_LIST *pxMailboxNode = NULL;

    if( NULL != pvMailboxHandle )
    {
        OSAL_MBOX_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxMailboxHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvMailbox != pvMailboxHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxMailboxNode = pxCurrentNode;
        }
    }

    return pxMailboxNode;
}

/**
 * @brief Searches for node in the event linked list that matches the handle.
 */
static OSAL_EVENT_STATS_LINKED_LIST* pxFindEvent( void* pvEventHandle )
{
    OSAL_EVENT_STATS_LINKED_LIST *pxEventNode = NULL;

    if( NULL != pvEventHandle )
    {
        OSAL_EVENT_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxEventHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvEvent != pvEventHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxEventNode = pxCurrentNode;
        }
    }

    return pxEventNode;
}

/**
 * @brief Searches for node in the timer linked list that matches the handle.
 */
static OSAL_TIMER_STATS_LINKED_LIST* pxFindTimer( void* pvTimerHandle )
{
    OSAL_TIMER_STATS_LINKED_LIST *pxTimerNode = NULL;

    if( NULL != pvTimerHandle )
    {
        OSAL_TIMER_STATS_LINKED_LIST *pxCurrentNode = pxOsStatsHandle->pxTimerHead;

        while( ( NULL != pxCurrentNode ) &&
               ( pxCurrentNode->pvTimer != pvTimerHandle ) )
        {
            pxCurrentNode = pxCurrentNode->pxNext;
        }
        if( NULL != pxCurrentNode )
        {
            pxTimerNode = pxCurrentNode;
        }
    }

    return pxTimerNode;
}

/**
 * @brief FreeRTOS Macro used to configure a timer for run-time stats.
 */
#ifdef RUN_TIME
void vConfigureTimerForRunTimeStats( void )
{
    uint32_t ulValue = 0;

    /* Disable PMU (Performance Monitoring Unit) */
    asm volatile( "MRC p15, 0, %0, c9, c12, 0" : "=r"( ulValue ) );
    ulValue &= ~( 1UL << 0 );
    asm volatile( "MCR p15, 0, %0, c9, c12, 0" :: "r"( ulValue ) );

    /* Clear overflow flags */
    asm volatile( "MCR p15, 0, %0, c9, c12, 3" :: "r"( 0x80000000ul ) );

    /* Enable PMU */
    asm volatile( "MRC p15, 0, %0, c9, c12, 0" : "=r"( ulValue ) );
    ulValue |= ( 1UL << 0 );
    asm volatile( "MCR p15, 0, %0, c9, c12, 0" :: "r"( ulValue ) );
}
#endif

/**
 * @brief FreeRTOS Macro used to get cycle count for run-time stats.
 */
#ifdef RUN_TIME
uint32_t vGetRunTimeCounterValue( void )
{
    uint32_t ulCycleCount = 0;

    /* Read PMU cycle count register */
    asm volatile( "MRC p15, 0, %0, c9, c13, 0" : "=r"( ulCycleCount ) );

    return ulCycleCount;
}
#endif

/**
 * @brief Sets stack size water mark for each task in linked list.
 */
static void vCalculateStackWatermark( void )
{
    TaskStatus_t *pxTaskStatusArray = NULL;
    UBaseType_t uxArraySize = uxTaskGetNumberOfTasks();
    uint32_t ulTotalRunTime = 0;

    pxTaskStatusArray = pvOSAL_MemAlloc( uxArraySize * sizeof( TaskStatus_t ) );

    if( NULL != pxTaskStatusArray )
    {
        uxArraySize = uxTaskGetSystemState( pxTaskStatusArray, uxArraySize, &ulTotalRunTime );

        int i = 0;

        for ( i = 0; i < uxArraySize; i++ )
        {
            OSAL_TASK_STATS_LINKED_LIST *pxCurrent = pxFindTask( pxTaskStatusArray[ i ].xHandle );

            if( NULL != pxCurrent)
            {
                pxCurrent->usTaskStackWaterMark = pxCurrent->usTaskStackSize - pxTaskStatusArray[ i ].usStackHighWaterMark * sizeof( StackType_t );
            }
        }

        vOSAL_MemFree( ( void ** )&pxTaskStatusArray );
    }
}

/**
 * @brief Sets CPU usage for each task in linked list.
 */
#ifdef FREERTOS_DEBUG
static void vCalculateCpuUsage( void )
{
    TaskStatus_t *pxTaskStatusArray = NULL;
    volatile UBaseType_t uxArraySize, x = 0;
    uint32_t ulTotalTime, ulStatsAsPercentage = 0;

    /* Ensures no task can switch states while measurments are taken */
    vOSAL_EnterCritical();

    ulTotalTime = portGET_RUN_TIME_COUNTER_VALUE();
    ulTotalTime /= 100UL;

    uxArraySize = uxTaskGetNumberOfTasks();

    pxTaskStatusArray = pvOSAL_MemAlloc( uxArraySize * sizeof( TaskStatus_t ) );

    if( NULL != pxTaskStatusArray )
    {
        uxArraySize = uxTaskGetSystemState( pxTaskStatusArray, uxArraySize, NULL );

        for( x = 0; x < uxArraySize; x++ )
        {
            TaskStatus_t xTaskStatus = pxTaskStatusArray[ x ];

            ulStatsAsPercentage = xTaskStatus.ulRunTimeCounter / ulTotalTime;

            OSAL_TASK_STATS_LINKED_LIST *pxCurrent = pxFindTask( pxTaskStatusArray[ x ].xHandle );
            if( NULL != pxCurrent )
            {
                if( OK == strcmp( pxCurrent->pcStatus, "Active" ) )
                {
                    pxCurrent->ulCpuUsagePercentage = ulStatsAsPercentage;
                }
            }
        }

        vOSAL_MemFree( ( void ** )&pxTaskStatusArray );
    }

    vOSAL_ExitCritical();
}
#endif
