/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the implementation of the Debug Access Library (DAL)
 *
 * @file dal.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"
#include "util.h"
#include "pll.h"

#include "osal.h"

#include "dal.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define DAL_NAME "DAL"

#define DAL_CMD_LEN_MIN    ( 1 )
#define DAL_CMD_SINGLE_LEN ( DAL_CMD_LEN_MIN + 1 )
#define DAL_CMD_FULL_MENU  ( '?' )
#define DAL_CMD_GO_TOP     ( '*' )
#define DAL_CMD_GO_BACK    ( '0' )

#define DAL_PROMPT        ( "#>" )
#define DAL_TOP_MENU_NAME ( "*" )

#define DAL_START_IDX ( 1 )
#define DAL_START_LVL ( 1 )

#define DAL_MAX_INPUT   ( 256 )
#define DAL_MSG_MAX_LEN ( 256 )

#define BASE_DEC ( 10 )
#define BASE_HEX ( 16 )

/* Stat & Error definitions */
#define DAL_STATS( DO )                        \
        DO( DAL_STATS_INIT_OVERALL_COMPLETE )  \
        DO( DAL_STATS_CREATE_MUTEX )           \
        DO( DAL_STATS_TAKE_MUTEX )             \
        DO( DAL_STATS_RELEASE_MUTEX )          \
        DO( DAL_STATS_OPTION_CREATED )         \
        DO( DAL_STATS_DIRECTORY_CREATED )      \
        DO( DAL_STATS_SUB_DIRECTORY_CREATED )  \
        DO( DAL_STATS_DEBUG_FUNCTION_CREATED ) \
        DO( DAL_STATS_NEW_COMMAND )            \
        DO( DAL_STATS_MAX )

#define DAL_ERRORS( DO )                              \
        DO( DAL_ERRORS_INIT_TASK_CREATE_FAILED )      \
        DO( DAL_ERRORS_INIT_MUTEX_CREATE_FAILED )     \
        DO( DAL_ERRORS_MUTEX_RELEASE_FAILED )         \
        DO( DAL_ERRORS_MUTEX_TAKE_FAILED )            \
        DO( DAL_ERRORS_OPTION_NOT_CREATED )           \
        DO( DAL_ERRORS_DIRECTORY_NOT_CREATED )        \
        DO( DAL_ERRORS_SUB_DIRECTORY_NOT_CREATED )    \
        DO( DAL_ERRORS_DEBUG_FUNCTION_NOT_CREATED )   \
        DO( DAL_ERRORS_VALIDATION_FAILED )            \
        DO( DAL_ERRORS_COMMAND_LIST_NULL_POINTER )    \
        DO( DAL_ERRORS_UNKNOWN_CHAR_IN_COMMAND_LINE ) \
        DO( DAL_ERRORS_UNKNOWN_COMMAND )              \
        DO( DAL_ERRORS_NULL_INPUT_POINTER )           \
        DO( DAL_ERRORS_WRONG_INPUT_BUF_SIZE )         \
        DO( DAL_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( DAL_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          DAL_STATS_STR[ x ],    \
                                          pxThis->ulStats[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( DAL_NAME,              \
                                          "%50s . . . . %d\r\n", \
                                          DAL_ERRORS_STR[ x ],   \
                                          pxThis->ulErrors[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < DAL_STATS_MAX ) pxThis->ulStats[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < DAL_ERRORS_MAX ) pxThis->ulErrors[ x ]++; }



/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    DAL_MENU_OPTION_TYPE_ENUM
 * @brief   Menu option types
 */
typedef enum DAL_MENU_OPTION_TYPE_ENUM
{
    DAL_MENU_OPTION_TYPE_DIR = 0,
    DAL_MENU_OPTION_TYPE_FUNC,
    MAX_DAL_MENU_OPTION_TYPE

} DAL_MENU_OPTION_TYPE_ENUM;

/**
 * @enum    DAL_STATS
 * @brief   Enumeration of stats counters for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( DAL_STATS, DAL_STATS, DAL_STATS_STR )

/**
 * @enum    DAL_ERRORS
 * @brief   Enumeration of stats errors for this application
 */
UTIL_MAKE_ENUM_AND_STRINGS( DAL_ERRORS, DAL_ERRORS, DAL_ERRORS_STR )


/******************************************************************************/
/* Structs/Unions                                                             */
/******************************************************************************/

/**
 * @union   DAL_MENU_ACTION
 * @brief   The possible actions an option can have
 */
typedef union DAL_MENU_ACTION
{
    DAL_DEBUG_FUNCTION pxDebugFunc;
    DAL_HDL            pxLevelDown;

} DAL_MENU_ACTION;

/**
 * @struct  DAL_MENU_OPTION
 * @brief   Single menu option
 */
typedef struct DAL_MENU_OPTION
{
    char                      pcName[ DAL_MAX_NAME_LEN ];
    DAL_MENU_OPTION_TYPE_ENUM xNodeType;

    DAL_MENU_ACTION           xAction;
    DAL_HDL                   pxLevelUp;

    DAL_HDL                   pxNextNode;
    DAL_HDL                   pxLastNode;
    int                       iNumNodes;
    int                       iDepth;

} DAL_MENU_OPTION;

/**
 * @struct  DAL_PRIVATE_DATA
 * @brief   Locally held private data
 */
typedef struct DAL_PRIVATE_DATA
{
    uint32_t           ulUpperFirewall;

    int                iIsInitialised;
    char               pcMenuName[ DAL_MAX_NAME_LEN ];
    DAL_DEBUG_FUNCTION pxInitFunc;

    int                iNumNodes;
    DAL_HDL            pxTopLevel;
    DAL_HDL            pxCurrentLevel;

    char               pcLastCmd[ DAL_MAX_INPUT ];

    void               *pvTaskHdl;
    void               *pvMtxHdl;

    uint32_t           ulStats[ DAL_STATS_MAX ];
    uint32_t           ulErrors[ DAL_ERRORS_MAX ];

    uint32_t           ulLowerFirewall;

} DAL_PRIVATE_DATA;


/******************************************************************************/
/* Private function declarations                                              */
/******************************************************************************/

/**
 * @brief   Display entire menu options
 *
 * @return  N/A
 */
static void vPrintMenu( void );

/**
 * @brief   vPrint the options in the currently selected level
 *
 * @return  N/A
 */
static void vPrintCurrentLevel( void );

/**
 * @brief   Display the options of an entire level
 *
 * @param   pxLevel     Level to display the options of
 * @param   iIncSubDirs TRUE  - recursively display all subdirectories
 *                      FALSE - only display this level
 *
 * @return  N/A
 */
static void vPrintNextLevel( DAL_HDL pxLevel, int iIncSubDirs );

/**
 * @brief   Add a new item to the menu
 *
 * @param   pcItemName  Name of the new item
 * @param   pxParent    Directory to add this item within
 * @param   pxFunction  [Optional] Function pointer (if this is a debug function)
 *
 * @return  Handle to the newly created item (NULL if not created)
 */
static DAL_HDL xNewMenuItem( const char *pcItemName, DAL_HDL pxParent, DAL_DEBUG_FUNCTION pxFunction );

/**
 * @brief   Select an option with the current available options
 *
 * @param   iCmd        Option selected
 *
 * @return  OK          New option selected
 *          ERROR       Option could not be carried out
 */
static int iSelectOption( int iCmd );

/**
 * @brief   Blocking function that wait for user input
 *
 * @param   pcInput         Pointer to the input buffer
 * @param   iInputBufsize   Input buffer size
 *
 * @return  Number of characters inputted by the user
 *
 * @note    RETURN key counts as 1 character
 */
static int iNextInput( char *pcInput, int iInputBufSize );

/**
 * @brief Local function that process each command
 *
 * @param pcCmd         Pointer to command
 * @param iInputLen     Input length
 *
 * @return  N/A         Does not return
 */
static void vProcessCmd( char *pcCmd, int iInputLen );

/**
 * @brief   Local task that pends on user commands and reacts to them
 *
 * @param   pArg        Pointer to task args (unused)
 *
 * @return  N/A         Does not return
 */
static void vDalTask( void *pArg );


/******************************************************************************/
/* Local data                                                                 */
/******************************************************************************/

static DAL_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iIsInitialised  */
    {
        0
    },                                                                         /* pcMenuName      */
    NULL,                                                                      /* pxInitFunc      */
    0,                                                                         /* iNumNodes       */
    NULL,                                                                      /* pxTopLevel      */
    NULL,                                                                      /* pxCurrentLevel  */
    {
        0
    },                                                                         /* pcLastCmd       */
    NULL,                                                                      /* pvTaskHdl       */
    NULL,                                                                      /* pvMtxHdl        */
    {
        0
    },                                                                         /* ulStats         */
    {
        0
    },                                                                         /* ulErrors        */
    LOWER_FIREWALL
};

static DAL_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Public function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initialise the DAL and start the debug monitoring menu
 */
int iDAL_Initialise( const char *pcMenuName,
                     uint32_t ulTaskPrio,
                     uint32_t ulStackSize,
                     DAL_DEBUG_FUNCTION pxPrintInitBanner )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pcMenuName ) &&
        ( DAL_MAX_NAME_LEN >= strlen( pcMenuName ) ) &&
        ( FALSE == pxThis->iIsInitialised ) &&
        ( NULL != pxPrintInitBanner ) )
    {
        if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvMtxHdl, "DAL_Mutex" ) )
        {
            PLL_ERR( DAL_NAME, "Error initialising mutex\r\n" );
            INC_ERROR_COUNTER( DAL_ERRORS_INIT_MUTEX_CREATE_FAILED )
        }
        else if( OSAL_ERRORS_NONE != iOSAL_Task_Create( &pxThis->pvTaskHdl,
                                                        vDalTask,
                                                        ulStackSize,
                                                        NULL,
                                                        ulTaskPrio,
                                                        "DAL_Task" ) )
        {
            INC_ERROR_COUNTER( DAL_ERRORS_INIT_TASK_CREATE_FAILED )
            PLL_ERR( DAL_NAME, "Error initialising task\r\n" );
        }
        else
        {
            INC_STAT_COUNTER( DAL_STATS_CREATE_MUTEX )

            pxThis->pxTopLevel = pvOSAL_MemAlloc( sizeof( DAL_MENU_OPTION ) );
            if( NULL != pxThis->pxTopLevel )
            {
                INC_STAT_COUNTER( DAL_STATS_OPTION_CREATED )

                pcOSAL_StrNCpy( pxThis->pcMenuName, pcMenuName, strlen( pcMenuName ) );
                pvOSAL_MemCpy( pxThis->pxTopLevel->pcName, DAL_TOP_MENU_NAME, strlen( DAL_TOP_MENU_NAME ) );
                pxThis->pxTopLevel->pxNextNode          = NULL;
                pxThis->pxTopLevel->pxLastNode          = NULL;
                pxThis->pxTopLevel->iNumNodes           = 0;
                pxThis->pxTopLevel->xAction.pxLevelDown = NULL;
                pxThis->pxTopLevel->pxLevelUp           = NULL;
                pxThis->pxTopLevel->xNodeType           = DAL_MENU_OPTION_TYPE_DIR;

                pxThis->pxCurrentLevel = pxThis->pxTopLevel;

                INC_STAT_COUNTER( DAL_STATS_INIT_OVERALL_COMPLETE )

                pxThis->pxInitFunc     = pxPrintInitBanner;
                pxThis->iIsInitialised = TRUE;
                iStatus                = OK;
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_OPTION_NOT_CREATED )
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Add a new directory to the top level of the DAL menu structure
 */
DAL_HDL pxDAL_NewDirectory( const char *pcDirName )
{
    DAL_MENU_OPTION *pxNewDir = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcDirName ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( DAL_STATS_TAKE_MUTEX )

            pxNewDir = xNewMenuItem( pcDirName, pxThis->pxTopLevel, NULL );

            if( NULL != pxNewDir )
            {
                INC_STAT_COUNTER( DAL_STATS_DIRECTORY_CREATED );
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_DIRECTORY_NOT_CREATED );
            }

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( DAL_STATS_RELEASE_MUTEX )
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_RELEASE_FAILED )
            }
        }
        else
        {
            INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return pxNewDir;
}

/**
 * @brief   Add a new subdirectory within an existing directory
 */
DAL_HDL pxDAL_NewSubDirectory( const char *pcSubDirName, DAL_HDL pxParent )
{
    DAL_MENU_OPTION *pxNewSubDir = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcSubDirName ) &&
        ( NULL != pxParent ) )
    {
        if( DAL_MENU_OPTION_TYPE_DIR == pxParent->xNodeType )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( DAL_STATS_TAKE_MUTEX )

                pxNewSubDir = xNewMenuItem( pcSubDirName, pxParent, NULL );

                if( NULL != pxNewSubDir )
                {
                    INC_STAT_COUNTER( DAL_STATS_SUB_DIRECTORY_CREATED );
                }
                else
                {
                    INC_ERROR_COUNTER( DAL_ERRORS_SUB_DIRECTORY_NOT_CREATED );
                }

                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
                {
                    INC_STAT_COUNTER( DAL_STATS_RELEASE_MUTEX )
                }
                else
                {
                    INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_RELEASE_FAILED )
                }
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_TAKE_FAILED )
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return pxNewSubDir;
}

/**
 * @brief   Add a new debug function within an existing directory
 */
DAL_HDL pxDAL_NewDebugFunction( const char *pcFunctionName, DAL_HDL pxParent, DAL_DEBUG_FUNCTION pxFunction )
{
    DAL_MENU_OPTION *pxNewFunc = NULL;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcFunctionName ) &&
        ( NULL != pxParent ) &&
        ( NULL != pxFunction ) )
    {
        if( DAL_MENU_OPTION_TYPE_DIR == pxParent->xNodeType )
        {
            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
            {
                INC_STAT_COUNTER( DAL_STATS_TAKE_MUTEX )

                pxNewFunc = xNewMenuItem( pcFunctionName, pxParent, pxFunction );

                if( NULL != pxNewFunc )
                {
                    INC_STAT_COUNTER( DAL_STATS_DEBUG_FUNCTION_CREATED );
                }
                else
                {
                    INC_ERROR_COUNTER( DAL_ERRORS_DEBUG_FUNCTION_NOT_CREATED );
                }

                if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
                {
                    INC_STAT_COUNTER( DAL_STATS_RELEASE_MUTEX )
                }
                else
                {
                    INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_RELEASE_FAILED )
                }
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_TAKE_FAILED )
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return pxNewFunc;
}

/**
 * @brief   Retrieve a user-inputted decimal integer
 */
int iDAL_GetInt( const char *pcPrompt, int *piInput )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != piInput ) )
    {
        int  iInputLen                   = 0;
        char pcGetInput[ DAL_MAX_INPUT ] =
        {
            0
        };

        while( OK != iStatus )
        {
            vPLL_Printf( "\r\n%s-%s ", pcPrompt, DAL_PROMPT );

            iInputLen = iNextInput( pcGetInput, sizeof( pcGetInput ) );
            if( DAL_CMD_LEN_MIN < iInputLen )
            {
                char *pcDigit = &pcGetInput[ 0 ];
                iStatus = OK;

                while( ( 0 < iInputLen ) && ( '\0' != *pcDigit ) )
                {
                    if( ( '\r' == *pcDigit ) || ( '\n' == *pcDigit ) )
                    {
                        break;
                    }
                    else if( ( '0' > *pcDigit ) || ( '9' < *pcDigit ) )
                    {
                        iStatus = ERROR;
                        break;
                    }
                    iInputLen--;
                    pcDigit++;
                }

                if( ( 0 < iInputLen ) && ( OK == iStatus ) )
                {
                    /* input is a number */
                    *piInput = ( int )strtol( pcGetInput, NULL, BASE_DEC );
                    vPLL_Printf( "\r\n" );
                }
                else
                {
                    vPLL_Printf( "Not a valid input\r\n" );
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Retrieve a user-inputted decimal integer within a range
 */
int iDAL_GetIntInRange( const char *pcPrompt, int *piInput, int iMin, int iMax )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != piInput ) )
    {
        char pcPromptWithRange[ DAL_MSG_MAX_LEN ] =
        {
            0
        };

        snprintf( pcPromptWithRange, DAL_MSG_MAX_LEN, "%s (Min : %d, Max: %d)", pcPrompt, iMin, iMax );
        if( iMin < iMax )
        {
            int iInput = 0;
            do
            {
                iStatus = iDAL_GetInt( ( const char* )pcPromptWithRange, &iInput );
                if( OK == iStatus )
                {
                    if( ( iInput < iMin ) || ( iInput > iMax ) )
                    {
                        vPLL_Printf( "Value must be within %d and %d\r\n", iMin, iMax );
                        iStatus = ERROR;
                    }
                    else
                    {
                        *piInput = iInput;
                    }
                }
            } while( OK != iStatus );
        }
    }

    return iStatus;
}

/**
 * @brief Retrieve a user-inputted float number
 */
int iDAL_GetFloat( const char *pcPrompt, float *pfInput )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != pfInput ) )
    {
        int  iInputLen                   = 0;
        int  iDotFlag                    = 0;
        char pcGetInput[ DAL_MAX_INPUT ] =
        {
            0
        };

        while( OK != iStatus )
        {
            vPLL_Printf( "\r\n%s-%s ", pcPrompt, DAL_PROMPT );

            iInputLen = iNextInput( pcGetInput, sizeof( pcGetInput ) );
            if( DAL_CMD_LEN_MIN < iInputLen )
            {
                char *pcDigit = &pcGetInput[ 0 ];
                iStatus = OK;

                while( ( 0 < iInputLen ) && ( '\0' != *pcDigit ) )
                {
                    if( ( '\r' == *pcDigit ) || ( '\n' == *pcDigit ) )
                    {
                        break;
                    }
                    else if( '.' == *pcDigit )
                    {
                        if( 0 == iDotFlag )
                        {
                            iDotFlag++;
                        }
                        else
                        {
                            iStatus = ERROR;
                            break;
                        }
                    }
                    else if( ( '0' > *pcDigit ) || ( '9' < *pcDigit ) )
                    {
                        iStatus = ERROR;
                        break;
                    }
                    iInputLen--;
                    pcDigit++;
                }

                if( ( 0 < iInputLen ) && ( OK == iStatus ) )
                {
                    /* input is a float number */
                    *pfInput = ( float )strtof( pcGetInput, NULL );
                    if( 0.0 == *pfInput )
                    {
                        vPLL_Printf( "Not a valid input\r\n" );
                    }
                    else
                    {
                        vPLL_Printf( "\r\n" );
                    }
                }
                else
                {
                    vPLL_Printf( "Not a valid input\r\n" );
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Retrieve a user-inputted float number within a range
 */
int iDAL_GetFloatInRange( const char *pcPrompt, float *pfInput, float fMin, float fMax )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != pfInput ) )
    {
        char pcPromptWithRange[ DAL_MSG_MAX_LEN ] =
        {
            0
        };

        snprintf( pcPromptWithRange, DAL_MSG_MAX_LEN, "%s (Min : %f, Max: %f)", pcPrompt, fMin, fMax );
        if( fMin < fMax )
        {
            float fInput = 0;
            do
            {
                iStatus = iDAL_GetFloat( ( const char* )pcPromptWithRange, &fInput );
                if( OK == iStatus )
                {
                    if( ( fInput < fMin ) || ( fInput > fMax ) )
                    {
                        vPLL_Printf( "Value must be within %f and %f\r\n", fMin, fMax );
                        iStatus = ERROR;
                    }
                    else
                    {
                        *pfInput = fInput;
                    }
                }
            } while( OK != iStatus );
        }
    }

    return iStatus;
}

/**
 * @brief   Retrieve a user-inputted hexadecimal number
 */
int iDAL_GetHex( const char *pcPrompt, uint32_t *pulInput )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != pulInput ) )
    {
        int  iInputLen                   = 0;
        char pcGetInput[ DAL_MAX_INPUT ] =
        {
            0
        };

        while( OK != iStatus )
        {
            vPLL_Printf( "\r\n%s-%s 0x", pcPrompt, DAL_PROMPT );

            iInputLen = iNextInput( pcGetInput, sizeof( pcGetInput ) );
            if( DAL_CMD_LEN_MIN < iInputLen )
            {
                char *pcDigit = &pcGetInput[ 0 ];
                iStatus = OK;

                while( ( 0 < iInputLen ) && ( '\0' != *pcDigit ) )
                {
                    if( ( '\r' == *pcDigit ) || ( '\n' == *pcDigit ) )
                    {
                        break;
                    }
                    else if( ( ( '0' > *pcDigit ) || ( '9' < *pcDigit ) ) &&
                             ( ( 'a' > *pcDigit ) || ( 'f' < *pcDigit ) ) &&
                             ( ( 'A' > *pcDigit ) || ( 'F' < *pcDigit ) ) )
                    {
                        iStatus = ERROR;
                        break;
                    }
                    iInputLen--;
                    pcDigit++;
                }

                if( ( 0 < iInputLen ) && ( OK == iStatus ) )
                {
                    /* input is a number */
                    *pulInput = ( uint32_t )strtoul( pcGetInput, NULL, BASE_HEX );
                    vPLL_Printf( "\r\n" );
                }
                else
                {
                    vPLL_Printf( "Not a valid input\r\n" );
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Retrieve a user-inputted hexadecimal number within a range
 */
int iDAL_GetHexInRange( const char *pcPrompt, uint32_t *pulInput, uint32_t ulMin, uint32_t ulMax )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != pulInput ) )
    {
        char pcPromptWithRange[ DAL_MSG_MAX_LEN ] =
        {
            0
        };

        snprintf( pcPromptWithRange,
                  DAL_MSG_MAX_LEN,
                  "%s (Min : 0x%X, Max: 0x%X)",
                  pcPrompt,
                  ( unsigned int )ulMin,
                  ( unsigned int )ulMax );
        if( ulMin < ulMax )
        {
            uint32_t ulInput = 0x00;
            do
            {
                iStatus = iDAL_GetHex( ( const char* )pcPromptWithRange, &ulInput );
                if( ( ulInput < ulMin ) || ( ulInput > ulMax ) )
                {
                    vPLL_Printf( "Value must be within 0x%X and 0x%X\r\n", ulMin, ulMax );
                    iStatus = ERROR;
                }
                else
                {
                    *pulInput = ulInput;
                }
            } while( OK != iStatus );
        }
    }

    return iStatus;
}

/**
 * @brief   Retrieve a user-inputted ASCII string
 */
int iDAL_GetString( const char *pcPrompt, char *pcInput, int iMaxLen )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) &&
        ( NULL != pcPrompt ) &&
        ( NULL != pcInput ) &&
        ( DAL_MAX_INPUT >= iMaxLen ) )
    {
        int  iInputLen                   = 0;
        char pcGetInput[ DAL_MAX_INPUT ] =
        {
            0
        };

        while( OK != iStatus )
        {
            vPLL_Printf( "\r\n%s-%s ", pcPrompt, DAL_PROMPT );

            iInputLen = iNextInput( pcGetInput, sizeof( pcGetInput ) );
            if( DAL_CMD_LEN_MIN < iInputLen )
            {
                /* don't copy last character as it's the RETURN key */
                iInputLen -= DAL_CMD_LEN_MIN;

                if( iMaxLen >= iInputLen )
                {
                    pcOSAL_StrNCpy( pcInput, pcGetInput, iInputLen );
                    vPLL_Printf( "\r\n" );
                    iStatus = OK;
                }
                else
                {
                    vPLL_Printf( "Input length (%d) exceeds maximum length (%d)\r\n",
                                 iInputLen,
                                 iMaxLen );
                }
            }
        }
    }

    return iStatus;
}

/**
 * @brief   Display the current stats/errors
 */
int iDAL_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( DAL_NAME, "============================================================\n\r" );
        PLL_INF( DAL_NAME, "DAL Proxy Statistics:\n\r" );
        for( i = 0; i < DAL_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( DAL_NAME, "------------------------------------------------------------\n\r" );
        PLL_INF( DAL_NAME, "DAL Proxy Errors:\n\r" );
        for( i = 0; i < DAL_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( DAL_NAME, "============================================================\n\r" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Set all stats/error values back to zero
 */
int iDAL_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        pvOSAL_MemSet( pxThis->ulStats, 0, sizeof( pxThis->ulStats ) );
        pvOSAL_MemSet( pxThis->ulErrors, 0, sizeof( pxThis->ulErrors ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( DAL_ERRORS_VALIDATION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Private function implementations                                           */
/******************************************************************************/

/**
 * @brief   Display entire menu options
 */
static void vPrintMenu( void )
{
    if( ( NULL != pxThis->pxTopLevel ) && ( TRUE == pxThis->iIsInitialised ) )
    {
        vPLL_Printf( "\r\n%s/\r\n", pxThis->pxTopLevel->pcName );
        vPrintNextLevel( pxThis->pxTopLevel->xAction.pxLevelDown, TRUE );
    }
}

/**
 * @brief   vPrint the options in the currently selected level
 */
static void vPrintCurrentLevel( void )
{
    if( NULL != pxThis->pxCurrentLevel )
    {
        vPLL_Printf( "\r\n%s/\r\n", pxThis->pxCurrentLevel->pcName );
        if( NULL != pxThis->pxCurrentLevel->pxLevelUp )
        {
            vPLL_Printf( "\t%d:../%s\r\n", 0,  pxThis->pxCurrentLevel->pxLevelUp->pcName );
        }
        vPrintNextLevel( pxThis->pxCurrentLevel->xAction.pxLevelDown, FALSE );
    }
}

/**
 * @brief   Display the options of an entire level
 */
static void vPrintNextLevel( DAL_HDL pxLevel, int iIncSubDirs )
{
    DAL_MENU_OPTION *pxCurrNode = pxLevel;
    int             iIndex      = DAL_START_IDX;

    while( NULL != pxCurrNode )
    {
        if( TRUE == iIncSubDirs )
        {
            int iDepth = 0;
            for( iDepth = 0; iDepth < pxCurrNode->iDepth; iDepth++ )
            {
                vPLL_Printf( "\t" );
            }
        }
        else
        {
            vPLL_Printf( "\t" );
        }

        vPLL_Printf( "%d:%s%s\r\n",
                     iIndex,
                     pxCurrNode->pcName,
                     ( DAL_MENU_OPTION_TYPE_DIR == pxCurrNode->xNodeType )?( "/" ):( "()" ) );

        if( ( TRUE == iIncSubDirs ) &&
            ( DAL_MENU_OPTION_TYPE_DIR == pxCurrNode->xNodeType ) &&
            ( NULL != pxCurrNode->xAction.pxLevelDown ) )
        {
            vPrintNextLevel( pxCurrNode->xAction.pxLevelDown, TRUE );
        }

        pxCurrNode = pxCurrNode->pxNextNode;
        iIndex++;
    }
}

/**
 * @brief   Add a new item to the menu
 */
static DAL_HDL xNewMenuItem( const char *pcItemName, DAL_HDL pxParent, DAL_DEBUG_FUNCTION pxFunction )
{
    DAL_MENU_OPTION *pxNewNode = NULL;

    /* pxFunction is an optional variable */

    if( ( NULL != pcItemName ) && ( NULL != pxParent ) &&
        ( DAL_MAX_NAME_LEN >= strlen( pcItemName ) ) &&
        ( DAL_MENU_OPTION_TYPE_DIR == pxParent->xNodeType ) &&
        ( TRUE == pxThis->iIsInitialised ) )
    {
        pxNewNode = ( DAL_MENU_OPTION* )pvOSAL_MemAlloc( sizeof( DAL_MENU_OPTION ) );
        if( NULL != pxNewNode )
        {
            INC_STAT_COUNTER( DAL_STATS_OPTION_CREATED )

            pcOSAL_StrNCpy( pxNewNode->pcName, pcItemName, strlen( pcItemName ) );
            pxNewNode->pxNextNode          = NULL;
            pxNewNode->pxLastNode          = NULL;
            pxNewNode->iNumNodes           = 0;
            pxNewNode->xAction.pxLevelDown = NULL;
            pxNewNode->pxLevelUp           = pxParent;

            if( NULL != pxFunction )
            {
                pxNewNode->xNodeType           = DAL_MENU_OPTION_TYPE_FUNC;
                pxNewNode->xAction.pxDebugFunc = pxFunction;
            }
            else
            {
                pxNewNode->xNodeType           = DAL_MENU_OPTION_TYPE_DIR;
                pxNewNode->xAction.pxDebugFunc = NULL;
            }

            /* append to parent directory */
            pxParent->iNumNodes++;
            pxNewNode->iDepth = pxParent->iDepth + 1;

            if( NULL == pxParent->xAction.pxLevelDown )
            {
                /* no subdirectory level yet, add this new one as the first */
                pxParent->xAction.pxLevelDown             = pxNewNode;
                pxParent->xAction.pxLevelDown->pxNextNode = NULL;
                pxParent->xAction.pxLevelDown->pxLastNode = pxParent->xAction.pxLevelDown->pxNextNode;
                pxParent->xAction.pxLevelDown->iNumNodes  = 1;
            }
            else
            {
                /* subdirectory level exists, add this new one to it */
                if( NULL == pxParent->xAction.pxLevelDown->pxNextNode )
                {
                    /*first item in this level */
                    pxParent->xAction.pxLevelDown->pxNextNode = pxNewNode;
                    pxParent->xAction.pxLevelDown->pxLastNode = pxNewNode;
                }
                else
                {
                    /* add to end of this level */
                    pxParent->xAction.pxLevelDown->pxLastNode->pxNextNode = pxNewNode;
                    pxParent->xAction.pxLevelDown->pxLastNode             = pxNewNode;
                }
                pxParent->xAction.pxLevelDown->iNumNodes++;
            }
        }
        else
        {
            INC_ERROR_COUNTER( DAL_ERRORS_OPTION_NOT_CREATED );
        }
    }

    return pxNewNode;
}

/**
 * @brief   Select an option with the current available options
 */
static int iSelectOption( int iCmd )
{
    int     iStatus        = ERROR;
    DAL_HDL pxCurrentLevel = pxThis->pxCurrentLevel;

    if( ( 0 < iCmd ) &&
        ( NULL != pxCurrentLevel ) &&
        ( iCmd <= pxCurrentLevel->iNumNodes ) )
    {
        int i = DAL_START_IDX;
        pxCurrentLevel = pxCurrentLevel->xAction.pxLevelDown;

        while( ( NULL != pxCurrentLevel ) && ( i++ < iCmd ) )
        {
            pxCurrentLevel = pxCurrentLevel->pxNextNode;
        }

        if( NULL != pxCurrentLevel )
        {
            if( DAL_MENU_OPTION_TYPE_DIR == pxCurrentLevel->xNodeType )
            {
                pxThis->pxCurrentLevel = pxCurrentLevel;
                iStatus                = OK;
            }
            else if( DAL_MENU_OPTION_TYPE_FUNC == pxCurrentLevel->xNodeType )
            {
                if( NULL != pxCurrentLevel->xAction.pxDebugFunc )
                {
                    vPLL_Printf( "\r\n" );
                    pxCurrentLevel->xAction.pxDebugFunc();
                    iStatus = OK;
                }
            }
        }

    }

    return iStatus;
}

/**
 * @brief   Blocking function that wait for user input
 */
static int iNextInput( char *pcInput, int iInputBufSize )
{
    int  iInputLen = 0;
    char cLastChar = '\0';

    if( NULL == pcInput )
    {
        INC_ERROR_COUNTER( DAL_ERRORS_NULL_INPUT_POINTER )
    }
    else
    {
        if( DAL_MAX_INPUT < iInputBufSize )
        {
            INC_ERROR_COUNTER( DAL_ERRORS_WRONG_INPUT_BUF_SIZE );
        }
        else
        {
            pvOSAL_MemSet( pcInput, 0, iInputBufSize );
            fflush( stdin );

            while( ( '\r' != cLastChar ) && ( '\n' != cLastChar ) &&
                   ( DAL_MAX_INPUT > iInputLen ) )
            {
                cLastChar              = cOSAL_GetChar();
                pcInput[ iInputLen++ ] = cLastChar;
                vPLL_Printf( "%c", cLastChar );
            }
        }
    }

    return iInputLen;
}

/**
 * @brief   Local function that process each command
 */
static void vProcessCmd( char *pcCmd, int iInputLen )
{
    int  iCmd         = 0;
    char *pcCmdCursor = pcCmd;
    char *pcEndPtr    = NULL;

    if( DAL_CMD_LEN_MIN == iInputLen )
    {
        vPrintCurrentLevel();
    }
    else
    {
        if( NULL != pcCmd )
        {
            while( '\r' != *pcCmdCursor )
            {
                iCmd = ( int ) strtol( pcCmdCursor, &pcEndPtr, BASE_DEC );
                if( 0 != iCmd )
                {
                    if( OK != iSelectOption( iCmd ) )
                    {
                        vPLL_Printf( "Unknown command (%d)\r\n", iCmd );
                        INC_ERROR_COUNTER( DAL_ERRORS_UNKNOWN_COMMAND )
                        break;
                    }
                    else
                    {
                        vPrintCurrentLevel();
                    }
                }
                else
                {
                    switch( *pcCmdCursor )
                    {
                    case DAL_CMD_FULL_MENU:
                    {
                        vPrintMenu();
                        pcEndPtr = ++pcCmdCursor;
                    }
                    break;

                    case DAL_CMD_GO_TOP:
                    {
                        if( NULL != pxThis->pxTopLevel )
                        {
                            pxThis->pxCurrentLevel = pxThis->pxTopLevel;
                        }
                        vPrintCurrentLevel();
                        pcEndPtr = ++pcCmdCursor;
                    }
                    break;

                    case DAL_CMD_GO_BACK:
                    {
                        if( NULL != pxThis->pxCurrentLevel->pxLevelUp )
                        {
                            pxThis->pxCurrentLevel = pxThis->pxCurrentLevel->pxLevelUp;
                        }
                        vPrintCurrentLevel();
                    }
                    break;

                    default:
                    {
                        vPLL_Printf( "Unknown command: (%c)\r\n", *pcCmdCursor );
                        INC_ERROR_COUNTER( DAL_ERRORS_UNKNOWN_COMMAND )
                        * pcEndPtr = '\r';
                    }
                    break;
                    }
                }

                if( NULL != pcEndPtr )
                {
                    pcCmdCursor = pcEndPtr;

                    if( '\r' != *pcCmdCursor )
                    {
                        pcCmdCursor++;
                    }

                    if( ( ' ' != *pcEndPtr ) && ( '\r' != *pcEndPtr ) )
                    {
                        vPLL_Printf( "Multiple commands need empty character in between\r\n" );
                        INC_ERROR_COUNTER( DAL_ERRORS_UNKNOWN_CHAR_IN_COMMAND_LINE );
                        break;
                    }
                }
                else
                {
                    break;
                }
            }
        }
        else
        {
            INC_ERROR_COUNTER( DAL_ERRORS_COMMAND_LIST_NULL_POINTER );
        }
    }
}

/**
 * @brief   Local task that pends on user commands and reacts to them
 */
static void vDalTask( void *pArg )
{
    int iInputLen = 0;

    /* Call the initialisation function if provided */
    if( NULL != pxThis->pxInitFunc )
    {
        pxThis->pxInitFunc();
    }

    FOREVER
    {
        iInputLen = iNextInput( pxThis->pcLastCmd, sizeof( pxThis->pcLastCmd ) );
        INC_STAT_COUNTER( DAL_STATS_NEW_COMMAND )

        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvMtxHdl, OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            INC_STAT_COUNTER( DAL_STATS_TAKE_MUTEX )
            vProcessCmd( pxThis->pcLastCmd, iInputLen );
            vPLL_Printf( "\r\n%s[%s]%s ",
                         pxThis->pcMenuName,
                         pxThis->pxCurrentLevel->pcName,
                         DAL_PROMPT );

            if( OSAL_ERRORS_NONE == iOSAL_Mutex_Release( pxThis->pvMtxHdl ) )
            {
                INC_STAT_COUNTER( DAL_STATS_RELEASE_MUTEX )
            }
            else
            {
                INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_RELEASE_FAILED )
            }
        }
        else
        {
            INC_ERROR_COUNTER( DAL_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
}
