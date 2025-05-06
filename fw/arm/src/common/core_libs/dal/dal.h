/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the public API of the Debug Access Library (DAL)
 *
 * @file dal.h
 *
 */
#ifndef _DAL_H_
#define _DAL_H_

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include "standard.h"


/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#ifndef DAL_MAX_NAME_LEN
#define DAL_MAX_NAME_LEN    ( 50 )
#endif


/******************************************************************************/
/* Typedefs                                                                   */
/******************************************************************************/

/**
 * @typedef DAL_DEBUG_FUNCTION
 * @brief   Typedef of a debug function handled by the DAL
 */
typedef void ( *DAL_DEBUG_FUNCTION )( void );


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  DAL_HDL
 * @brief   Handle to an option in the debug menu
 */
typedef struct DAL_MENU_OPTION * DAL_HDL;


/******************************************************************************/
/* Public function declarations                                               */
/******************************************************************************/

/**
 * @brief   Initialise the DAL and start the debug monitoring menu
 *
 * @param   pcMenuName        Name of this debug session
 * @param   ulTaskPrio        Priority of the DAL task
 * @param   ulStackSize       Stack allocated to the DAL task
 * @param   pxPrintInitBanner Function to print initialisation banner
 *
 * @return  OK if DAL is initialised and running successfully
 *          ERROR if the DAL is not initialised
 */ 
int iDAL_Initialise( const char *pcMenuName,
                     uint32_t ulTaskPrio,
                     uint32_t ulStackSize,
                     DAL_DEBUG_FUNCTION pxPrintInitBanner );

/**
 * @brief   Add a new directory to the top level of the DAL menu structure
 *
 * @param   pcDirName       Name of the new directory
 *
 * @return  Handle to the new directory (NULL if not added)
 */
DAL_HDL pxDAL_NewDirectory( const char *pcDirName );

/**
 * @brief   Add a new subdirectory within an existing directory
 *
 * @param   pcSubDirName    Name of the new directory
 * @param   pxParent        Handle to the directory to add this to
 *
 * @return  Handle to the new directory (NULL if not added)
 */
DAL_HDL pxDAL_NewSubDirectory( const char *pcSubDirName, DAL_HDL pxParent );

/**
 * @brief   Add a new debug function within an existing directory
 *
 * @param   pcFunctionName  Name of the new function
 * @param   pxParent        Handle to the directory to add this to
 *
 * @return  Handle to the new function (NULL if not added)
 */
DAL_HDL pxDAL_NewDebugFunction( const char *pcFunctionName, DAL_HDL pxParent, DAL_DEBUG_FUNCTION pxFunction );


/**
 * @brief   Retrieve a user-inputted decimal integer
 *
 * @param   pcPrompt    String to display to the user
 * @param   piInput     Pointer to int value that will be updated from user input
 *
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until an integer value is inputted
 */
int iDAL_GetInt( const char *pcPrompt, int *piInput );

/**
 * @brief   Retrieve a user-inputted decimal integer within a range
 *
 * @param   pcPrompt    String to display to the user
 * @param   piInput     Pointer to int value that will be updated from user input
 * @param   iMin        Minimum value allowed (inclusive)
 * @param   iMax        Maximum value allowed (inclusive)
 *
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until an integer value is inputted
 */
int iDAL_GetIntInRange( const char *pcPrompt, int *piInput, int iMin, int iMax );

/**
 * @brief Retrieve user-inputted float
 * 
 * @param   pcPrompt    String to display to the user
 * @param   pfInput     Pointer to float value that will be updated from user input
 * 
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until a float value is inputted
*/
int iDAL_GetFloat( const char *pcPrompt, float *pfInput );

/**
 * @brief Retrieve user-inputted float within range
 * 
 * @param   pcPrompt    String to display to the user
 * @param   pfInput     Pointer to float value that will be updated from user input
 * @param   fMin        Minimum value allowed (inclusive)
 * @param   fMax        Maximum value allowed (inclusive)
 * 
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until a float value is inputted
*/
int iDAL_GetFloatInRange( const char *pcPrompt, float *pfInput, float fMin, float fMax );

/**
 * @brief   Retrieve a user-inputted hexadecimal number
 *
 * @param   pcPrompt    String to display to the user
 * @param   pulInput    Pointer to hex value that will be updated from user input
 *
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until a hex value is inputted
 */
int iDAL_GetHex( const char *pcPrompt, uint32_t *pulInput );

/**
 * @brief   Retrieve a user-inputted hexadecimal number within a range
 *
 * @param   pcPrompt    String to display to the user
 * @param   pulInput    Pointer to hex value that will be updated from user input
 * @param   ulMin       Minimum value allowed (inclusive)
 * @param   ulMax       Maximum value allowed (inclusive)
 *
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until a hex value is inputted
 */
int iDAL_GetHexInRange( const char *pcPrompt, uint32_t *pulInput, uint32_t ulMin, uint32_t ulMax );

/**
 * @brief   Retrieve a user-inputted ASCII string
 *
 * @param   pcPrompt    String to display to the user
 * @param   pcInput     String that will be updated from user input
 * @param   iMaxLen     Maximum length of string to retrieve
 *
 * @return  OK          User inputted a valid value
 *          ERROR       User has not inputted a valid value
 *
 * @note    This is a block call - this function won't return until a string is inputted
 */
int iDAL_GetString( const char *pcPrompt, char *pcInput, int iMaxLen );

/**
 * @brief   Print all the stats gathered by the library
 *
 * @return  OK          Stats retrieved from the DAL successfully
 *          ERROR       Stats not retrieved successfully
 *
 */
int iDAL_PrintStatistics( void );

/**
 * @brief   Clear all the stats in the library
 *
 * @return  OK          Stats cleared successfully
 *          ERROR       Stats not cleared successfully
 *
 */
int iDAL_ClearStatistics( void );

#endif
