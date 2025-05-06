/**
 * Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
 * SPDX-License-Identifier: MIT
 *
 * This file contains the user API definitions for the OSPI device driver.
 *
 * @file ospi.c
 *
 */

/******************************************************************************/
/* Includes                                                                   */
/******************************************************************************/

#include <stdio.h>
#include <stdlib.h>

#include "xospipsv.h"                                                          /* OSPIPSV device driver */

#include "ospi.h"
#include "util.h"
#include "pll.h"

/******************************************************************************/
/* Defines                                                                    */
/******************************************************************************/

#define UPPER_FIREWALL ( 0xBABECAFE )
#define LOWER_FIREWALL ( 0xDEADFACE )

#define OSPI_NAME "OSPI"

/* Stat & Error definitions */
#define OSPI_STATS( DO ) DO( OSPI_STATS_INIT_COMPLETED ) DO( OSPI_STATS_ERASE_SUCCESS ) DO(            \
            OSPI_STATS_READ_SUCCESS ) DO( OSPI_STATS_WRITE_SUCCESS ) DO( OSPI_STATS_CREATE_TIMER ) DO( \
            OSPI_STATS_CREATE_MUTEX ) DO( OSPI_STATS_TAKE_MUTEX ) DO( OSPI_STATS_RELEASE_MUTEX ) DO( OSPI_STATS_MAX )

#define OSPI_ERRORS( DO ) DO( OSPI_ERRORS_VALIDAION_FAILED ) DO( OSPI_ERRORS_DEVICE_RESET ) DO(                       \
            OSPI_ERRORS_LOOKUP_CONFIG ) DO( OSPI_ERRORS_CONFIG_INIT ) DO( OSPI_ERRORS_SET_OPTIONS ) DO(               \
            OSPI_ERRORS_SET_CLK_PRESCALER ) DO( OSPI_ERRORS_SELECT_FLASH ) DO( OSPI_ERRORS_FLASH_READ_ID ) DO(        \
            OSPI_ERRORS_SET_DDR_MODE_INDEX ) DO( OSPI_ERRORS_4B_ADDRESS_MODE ) DO( OSPI_ERRORS_SET_SDR_DDR_MODE ) DO( \
            OSPI_ERRORS_PAGE_SIZE ) DO( OSPI_ERRORS_FLASH_ERASE_FAILED ) DO( OSPI_ERRORS_FLASH_READ_FAILED ) DO(      \
            OSPI_ERRORS_FLASH_LINEAR_WRITE_FAILED ) DO( OSPI_ERRORS_FLASH_WRITE_FAILED ) DO(                          \
            OSPI_ERRORS_FLASH_READ_MISMATCH ) DO( OSPI_ERRORS_FLASH_POLL_RETRY_FAILED ) DO(                           \
            OSPI_ERRORS_SET_EDGE_MODE ) DO( OSPI_ERRORS_SET_4B_ADDR_MODE ) DO( OSPI_ERRORS_TIMER_CREATE_FAILED ) DO(  \
            OSPI_ERRORS_TIMER_START_FAILED ) DO( OSPI_ERRORS_TIMER_STOP_FAILED ) DO(                                  \
            OSPI_ERRORS_MUTEX_CREATE_FAILED ) DO( OSPI_ERRORS_MUTEX_RELEASE_FAILED ) DO(                              \
            OSPI_ERRORS_MUTEX_TAKE_FAILED ) DO( OSPI_ERRORS_FLASH_ID_READ ) DO( OSPI_ERRORS_MAX )

#define PRINT_STAT_COUNTER( x )  PLL_INF( OSPI_NAME,             \
                                          "%50s . . . . %d\r\n", \
                                          OSPI_STATS_STR[ x ],   \
                                          pxThis->pulStatCounters[ x ] )
#define PRINT_ERROR_COUNTER( x ) PLL_INF( OSPI_NAME,             \
                                          "%50s . . . . %d\r\n", \
                                          OSPI_ERRORS_STR[ x ],  \
                                          pxThis->pulErrorCounters[ x ] )

#define INC_STAT_COUNTER( x )  { if( x < OSPI_STATS_MAX ) pxThis->pulStatCounters[ x ]++; }
#define INC_ERROR_COUNTER( x ) { if( x < OSPI_ERRORS_MAX ) pxThis->pulErrorCounters[ x ]++; }


/* Flash command Id's */
#define WRITE_STATUS_CMD         ( 0x01 )
#define WRITE_DISABLE_CMD        ( 0x04 )
#define WRITE_ENABLE_CMD         ( 0x06 )
#define BULK_ERASE_CMD           ( 0xC7 )
#define DIE_ERASE_CMD            ( 0xC4 )
#define READ_ID                  ( 0x9F )
#define READ_CONFIG_CMD          ( 0x35 )
#define WRITE_CONFIG_CMD         ( 0x01 )
#define READ_FLAG_STATUS_CMD     ( 0x70 )
#define WRITE_CMD_4B             ( 0x12 )
#define SEC_ERASE_CMD_4B         ( 0xDC )
#define SUBSEC_32KB_ERASE_CMD_4B ( 0x5C )
#define READ_CMD_OCTAL_IO_4B     ( 0xCC )
#define READ_CMD_OCTAL_DDR       ( 0x9D )
#define WRITE_CMD_OCTAL_4B       ( 0x84 )
#define ENTER_4B_ADDR_MODE       ( 0xB7 )
#define EXIT_4B_ADDR_MODE        ( 0xE9 )
#define WRITE_CONFIG_REG         ( 0x81 )
#define READ_CONFIG_REG          ( 0x85 )

#define SIXTEENMB ( 0x1000000 )

#define FLASH_PAGE_SIZE_DEFAULT ( 256 )
#define FLASH_SECTOR_SIZE_32KB  ( 0x8000 )
#define FLASH_SECTOR_SIZE_64KB  ( 0x10000 )
#define FLASH_SECTOR_SIZE_128KB ( 0x20000 )
#define FLASH_DEVICE_SIZE_256M  ( 0x2000000 )
#define FLASH_DEVICE_SIZE_512M  ( 0x4000000 )
#define FLASH_DEVICE_SIZE_1G    ( 0x8000000 )
#define FLASH_DEVICE_SIZE_2G    ( 0x10000000 )

#define MICRON_OCTAL_ID_BYTE0     ( 0x2c )
#define GIGADEVICE_OCTAL_ID_BYTE0 ( 0xc8 )
#define ISSI_OCTAL_ID_BYTE0       ( 0x9d )

#define OSPI_READ_BUFFER_SIZE       ( 8 )
#define OSPI_READ_BUFFER_ALIGNMENT  ( 8 )
#define OSPI_WRITE_BUFFER_ALIGNMENT ( 4 )
#define OSPI_DATA_ALIGNMENT         ( 8 )
#define OSPI_CMD_BUFFER_SIZE        ( 8 )
#define OSPI_STATUS_BUFFER_SIZE     ( 2 )

#define OSPI_POLL_OVERALL_TIMEOUT_MS  ( 1000 )
#define OSPI_POLL_INTERVAL_TIMEOUT_MS ( 100 )

#define BITSHIFT_1B ( 8 )
#define BITSHIFT_2B ( 16 )
#define BITSHIFT_3B ( 24 )

#define MISMATCH_CHECK_COUNT    ( 16 )
#define FLASH_ID_STR_BUFFER     ( 100 )
#define FLASH_ID_SPECIFIER_SIZE ( 6 )
#define FLASH_ID_READ_SIZE      ( 8 )
#define FLASH_WRITE_BYTE_SIZE   ( 8 )

#define XFLASH_CMD_ADDRSIZE_3      ( 3 )
#define XFLASH_CMD_ADDRSIZE_4      ( 4 )
#define XFLASH_BYTE_COUNT_1        ( 1 )
#define XFLASH_BYTE_COUNT_2        ( 2 )
#define XFLASH_OPCODE_DUMMY_CYCLES ( 8 )
#define XFLASH_STATUS_BYTE         ( 0x80 )


/******************************************************************************/
/* Enums                                                                      */
/******************************************************************************/

/**
 * @enum    OSPI_STATS
 * @brief   Enumeration of stats counters for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( OSPI_STATS, OSPI_STATS, OSPI_STATS_STR )

/**
 * @enum    OSPI_ERRORS
 * @brief   Enumeration of stats errors for this driver
 */
UTIL_MAKE_ENUM_AND_STRINGS( OSPI_ERRORS, OSPI_ERRORS, OSPI_ERRORS_STR )


/******************************************************************************/
/* Structs                                                                    */
/******************************************************************************/

/**
 * @struct  OSPI_FLASH_INFO
 * @brief   Structure describing a flash device
 */
typedef struct OSPI_FLASH_INFO
{
    uint32_t ulJedecId;                                                        /* JEDEC ID */
    uint32_t ulSectSize;                                                       /* Individual sector size or
                                                                                * combined sector size in case of parallel config*/
    uint32_t ululNumSect;                                                      /* Total no. of sectors in one/two flash devices */
    uint32_t ulPageSize;                                                       /* Individual page size or
                                                                                * combined page size in case of parallel config*/
    uint32_t ulNumPage;                                                        /* Total no. of pages in one/two flash devices */
    uint32_t ulFlashDeviceSize;                                                /* This is the size of one flash device */
    uint8_t  ucNumDie;                                                         /* No. of die forming a single flash */
    uint32_t ulReadCmd;                                                        /* Read command used to read data from flash */
    uint32_t ulWriteCmd;                                                       /* Write command used to write data to flash */
    uint32_t ulEraseCmd;                                                       /* Erase Command */
    uint8_t  ucStatusCmd;                                                      /* Status Command */
    uint8_t  ucDummyCycles;                                                    /* Number of Dummy cycles for Read operation */

} OSPI_FLASH_INFO;

/**
 * @struct  OSPI_PRIVATE_DATA
 * @brief   Structure to hold ths driver's private data
 */
typedef struct OSPI_PRIVATE_DATA
{
    uint32_t ulUpperFirewall;

    int      iInitialised;
    XOspiPsv xOspiPsvInstance;
    uint32_t ulFlashMake;
    uint32_t ulOspiSectorSize;
    uint8_t  ucFctIndex;
    uint32_t ulPageSize;
    uint8_t  ucOspiFlashPercentage;
    void     *pvOsalMutexHdl;
    void     *pvTimerHandle;
    int      iAbortPollWait;
    uint8_t  ucReadBfrPtr[ OSPI_READ_BUFFER_SIZE ] __attribute__ ( ( aligned ( OSPI_DATA_ALIGNMENT ) ) );

    uint32_t pulStatCounters[ OSPI_STATS_MAX ];
    uint32_t pulErrorCounters[ OSPI_ERRORS_MAX ];

    uint32_t ulLowerFirewall;

} OSPI_PRIVATE_DATA;


/******************************************************************************/
/* Local Variables                                                            */
/******************************************************************************/

/* Note: there are a number of hardcoded values here used to identify and config the flash device */
static OSPI_FLASH_INFO pxFlashConfigTable[] =
{
    /* Micron */
    {
        0x2c5b1a, FLASH_SECTOR_SIZE_128KB, 0x200, FLASH_PAGE_SIZE_DEFAULT, 0x40000,
        FLASH_DEVICE_SIZE_512M, 1,
        READ_CMD_OCTAL_IO_4B, ( WRITE_CMD_OCTAL_4B << BITSHIFT_1B ) | WRITE_CMD_4B,
        ( DIE_ERASE_CMD << BITSHIFT_2B ) | ( BULK_ERASE_CMD << BITSHIFT_1B ) | SEC_ERASE_CMD_4B,
        READ_FLAG_STATUS_CMD, 16
    },
    {
        0x2c5b1b, FLASH_SECTOR_SIZE_128KB, 0x400, FLASH_PAGE_SIZE_DEFAULT, 0x80000,
        FLASH_DEVICE_SIZE_1G, 1,
        READ_CMD_OCTAL_IO_4B, ( WRITE_CMD_OCTAL_4B << BITSHIFT_1B ) | WRITE_CMD_4B,
        ( DIE_ERASE_CMD << BITSHIFT_2B ) | ( BULK_ERASE_CMD << BITSHIFT_1B ) | SEC_ERASE_CMD_4B,
        READ_FLAG_STATUS_CMD, 16
    },
    {
        0x2c5b1c, FLASH_SECTOR_SIZE_32KB, 0x800, FLASH_PAGE_SIZE_DEFAULT, 0x100000,
        FLASH_DEVICE_SIZE_2G, 1,
        READ_CMD_OCTAL_IO_4B, ( WRITE_CMD_OCTAL_4B << BITSHIFT_1B ) | WRITE_CMD_4B,
        ( DIE_ERASE_CMD << BITSHIFT_2B ) | ( BULK_ERASE_CMD << BITSHIFT_1B ) | SUBSEC_32KB_ERASE_CMD_4B,
        READ_FLAG_STATUS_CMD, 16
    },
    /* GIGADEVICE */
    {
        0xc86819, FLASH_SECTOR_SIZE_64KB, 0x200, FLASH_PAGE_SIZE_DEFAULT, 0x20000,
        FLASH_DEVICE_SIZE_256M, 1,
        READ_CMD_OCTAL_IO_4B, ( WRITE_CMD_OCTAL_4B << BITSHIFT_1B ) | WRITE_CMD_4B,
        ( DIE_ERASE_CMD << BITSHIFT_2B ) | ( BULK_ERASE_CMD << BITSHIFT_1B ) | SEC_ERASE_CMD_4B,
        READ_FLAG_STATUS_CMD, 16
    },
    /* ISSI */
    {
        0x9d5b19, FLASH_SECTOR_SIZE_128KB, 0x100, FLASH_PAGE_SIZE_DEFAULT, 0x20000,
        FLASH_DEVICE_SIZE_256M, 1,
        READ_CMD_OCTAL_IO_4B, ( WRITE_CMD_OCTAL_4B << BITSHIFT_1B ) | WRITE_CMD_4B,
        ( DIE_ERASE_CMD << BITSHIFT_2B ) | ( BULK_ERASE_CMD << BITSHIFT_1B ) | SEC_ERASE_CMD_4B,
        READ_FLAG_STATUS_CMD, 16
    },
};


static OSPI_PRIVATE_DATA xLocalData =
{
    UPPER_FIREWALL,                                                            /* ulUpperFirewall */
    FALSE,                                                                     /* iInitialised */
    { {
          0
      } },                                                                     /* xOspiPsvInstance */
    0,                                                                         /* ulFlashMake */
    0,                                                                         /* ulOspiSectorSize */
    0,                                                                         /* ucFctIndex */
    0,                                                                         /* ulPageSize */
    0,                                                                         /* ucOspiFlashPercentage */
    NULL,                                                                      /* pvOsalMutexHdl */
    NULL,                                                                      /* pvTimerHandle */
    FALSE,                                                                     /* iAbortPollWait */
    {
        0
    },                                                                         /* ucReadBfrPtr */
    {
        0
    },                                                                         /* pulStatCounters */
    {
        0
    },                                                                         /* pulErrorCounters */
    LOWER_FIREWALL                                                             /* ulLowerFirewall */
};
static OSPI_PRIVATE_DATA *pxThis = &xLocalData;


/******************************************************************************/
/* Private Function declarations                                              */
/******************************************************************************/

/**
 * @brief   Reads the flash ID and identifies the flash in FCT table
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 *
 * @return  XST_SUCCESS         Successfully read
 *          XST_FAILURE         Failed to read the id
 */
static int iFlashReadId( XOspiPsv *pxOspiPsvPtr );

/**
 * @brief   This function erases the sectors in the  serial Flash connected to the
 *          OSPIPSV interface.
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   ulAddress           Contains the address to erase data to in the Flash
 * @param   ulByteCount         Contains the number of bytes to erase
 * @param   pucWriteBfrPtr      Pointer to the write buffer
 */
static int iFlashErase( XOspiPsv *pxOspiPsvPtr,
                        uint32_t ulAddress,
                        uint32_t ulByteCount,
                        uint8_t *pucWriteBfrPtr );

/**
 * @brief   Writes to the serial Flash connected to the OSPIPSV interface
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   ulAddress           Contains the address to write data to in the Flash
 * @param   ulByteCount         Contains the number of bytes to write
 * @param   pucWriteBfrPtr      Pointer to the write buffer to be transmitted
 */
static int iFlashWrite( XOspiPsv *pxOspiPsvPtr,
                        uint32_t ulAddress,
                        uint32_t ulByteCount,
                        uint8_t *pucWriteBfrPtr );

/**
 * @brief   Writes to the serial Flash connected to the OSPIPSV interface, this can be used
 *          when the controller is configured in linear mode
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   ulAddress           Contains the address to write data to in the Flash
 * @param   ulByteCount         Contains the number of bytes to write.
 * @param   pucWriteBfrPtr      Pointer to the write buffer to be transmitted
 */
static int iFlashLinearWrite( XOspiPsv *pxOspiPsvPtr,
                              uint32_t ulAddress,
                              uint32_t ulByteCount,
                              uint8_t *pucWriteBfrPtr );

/**
 * @brief   This function performs the read
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   ulAddress           The address of the first sector to read
 * @param   ulByteCount         Contains the total size to be erased
 * @param   pucReadBfrPtr       Pointer to the read buffer to which valid received data should be
 *                              written
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iFlashRead( XOspiPsv *pxOspiPsvPtr,
                       uint32_t ulAddress,
                       uint32_t ulByteCount,
                       uint8_t *pucReadBfrPtr );

/**
 * @brief   Performs a transfer on the bus in polled mode
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   xFlashMsg           The flash message structure
 */
static int iPollTransferWithRetry( XOspiPsv *pxOspiPsvPtr, XOspiPsv_Msg *pxFlashMsg );

/**
 * @brief   Find the FCT index based on the Id that was read
 *
 * @param   ulReadId            The Flash Id
 * @param   pucFctIndex         The returned Flash configuration Table (FCT) index
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE
 */
static int iFindFctIndex( uint32_t ulReadId, uint8_t *pucFctIndex );

/**
 * @brief   Set the flash device into Octal DDR mode or exit from octal DDR
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   iMode               The mode
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE
 */
static int iFlashSetSdrDdrModeEdgeMode( XOspiPsv *pxOspiPsvPtr, int iMode );

/**
 * @brief   Set the flash device into 4 byte addressing mode
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance.
 * @param   iEnable             Enable or disable
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iFlashSet4bAddrMode( XOspiPsv *pxOspiPsvPtr, int iEnable );

/**
 * @brief   This functions translates the address based on the type of interconnection
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance.
 * @param   ulAddress           The address which is to be accessed
 * @param   pulRealAddress      The translated address - for single it is unchanged; for stacked,
 *                              the lower flash size is subtracted
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iGetRealAddr( XOspiPsv *pxOspiPsvPtr, uint32_t ulAddress, uint32_t *pulRealAddress );

/**
 * @brief   Determine the number of lines used for command, address and data
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 * @param   ulAddress           Read(TRUE) or write(FALSE)
 * @param   pucNum              Number of lines
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iGetProtoType( XOspiPsv *pxOspiPsvPtr, int iRead, uint8_t *pucNum );

/**
 * @brief   This functions performs a bulk erase operation when the
 *          flash device has a single die
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iBulkErase( XOspiPsv *pxOspiPsvPtr );

/**
 * @brief   This functions performs a die erase operation on all the die in
 *          the flash device
 *
 * @param   pxOspiPsvPtr        The XOspiPsv driver instance
 *
 * @return  XST_SUCCESS if successful, else XST_FAILURE.
 */
static int iDieErase( XOspiPsv *pxOspiPsvPtr );

/**
 * @brief   Callback invoked whenever polling interval has been exceeded
 *
 * @param   pvTimerHandle       Pointer to OS Timer Handle.
 */
static void vTimerPollTimeoutCb( void *pvTimerHandle );


/******************************************************************************/
/* Public Function implementations                                            */
/******************************************************************************/

/**
 * @brief   Initializes the OSPI driver.
 */
int iOSPI_FlashInit( OSPI_CFG_TYPE *pxOspiCfg )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( FALSE == pxThis->iInitialised ) &&
        ( NULL != pxOspiCfg ) )
    {
        int iOspiStatus = XST_FAILURE;
        pxThis->ulPageSize = pxOspiCfg->usPageSize;

        XOspiPsv_Config *pxOspiPsvConfig = NULL;

        /* Timer created first as needed by the poll transfer function */
        if( OSAL_ERRORS_NONE != iOSAL_Timer_Create( &pxThis->pvTimerHandle,
                                                    OSAL_TIMER_CONFIG_ONE_SHOT,
                                                    vTimerPollTimeoutCb,
                                                    "ospi_poll_timeout" ) )
        {
            PLL_ERR( OSPI_NAME, "Error: iOSAL_Timer_Create failed\r\n" );
            INC_ERROR_COUNTER( OSPI_ERRORS_TIMER_CREATE_FAILED )
            iStatus = ERROR;
        }
        else
        {
            INC_STAT_COUNTER( OSPI_STATS_CREATE_TIMER )
            iStatus = OK;
        }

        if( OK == iStatus )
        {
            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Create( &pxThis->pvOsalMutexHdl,
                                                        "ami_proxy mutex" ) )
            {
                PLL_ERR( OSPI_NAME, "Error: initialising mutex\r\n" );
                INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_CREATE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( OSPI_STATS_CREATE_MUTEX )
            }
        }

        if( OK == iStatus )
        {
            /* Reset the device */
            iOspiStatus = XOspiPsv_DeviceReset( XOSPIPSV_HWPIN_RESET );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_DeviceReset failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_DEVICE_RESET )
                iStatus = ERROR;
            }
        }

        /* Initialize the OSPIPSV driver so that it's ready to use */
        if( OK == iStatus )
        {
            pxOspiPsvConfig = XOspiPsv_LookupConfig( pxOspiCfg->ucDeviceId );
            if( NULL == pxOspiPsvConfig )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_LookupConfig failed\r\n" );
                INC_ERROR_COUNTER( OSPI_ERRORS_LOOKUP_CONFIG )
                iStatus = ERROR;
            }
        }

        if( OK == iStatus )
        {
            iOspiStatus = XOspiPsv_CfgInitialize( &pxThis->xOspiPsvInstance, pxOspiPsvConfig );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_CfgInitialize failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_CONFIG_INIT )
                iStatus = ERROR;
            }
        }

        /* Enable IDAC controller in OSPI */
        if( OK == iStatus )
        {
            iOspiStatus = XOspiPsv_SetOptions( &pxThis->xOspiPsvInstance, XOSPIPSV_IDAC_EN_OPTION );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_SetOptions failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_SET_OPTIONS )
                iStatus = ERROR;
            }
        }

        /* Set the prescaler for OSPIPSV clock */
        if( OK == iStatus )
        {
            iOspiStatus = XOspiPsv_SetClkPrescaler( &pxThis->xOspiPsvInstance, XOSPIPSV_CLK_PRESCALE_12 );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_SetClkPrescaler failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_SET_CLK_PRESCALER )
                iStatus = ERROR;
            }
        }

        if( OK == iStatus )
        {
            iOspiStatus = XOspiPsv_SelectFlash( &pxThis->xOspiPsvInstance, XOSPIPSV_SELECT_FLASH_CS0 );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: XOspiPsv_SelectFlash failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_SELECT_FLASH )
                iStatus = ERROR;
            }
        }

        /*
         * Read flash ID and obtain all flash related information
         * It is important to call the read id function before
         * performing proceeding to any operation, including
         * preparing the WriteBuffer
         */
        if( OK == iStatus )
        {
            iOspiStatus = iFlashReadId( &pxThis->xOspiPsvInstance );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iFlashReadId failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_READ_ID )
                iStatus = ERROR;
            }
        }

        /* Set Flash device and Controller modes */
        if( OK == iStatus )
        {
            iOspiStatus = iFlashSetSdrDdrModeEdgeMode( &pxThis->xOspiPsvInstance, XOSPIPSV_EDGE_MODE_SDR_NON_PHY );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iFlashSetSdrDdrModeEdgeMode failed:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_SET_DDR_MODE_INDEX )
                iStatus = ERROR;
            }
        }

        if( OK == iStatus )
        {
            if( pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize > SIXTEENMB )
            {
                iOspiStatus = iFlashSet4bAddrMode( &pxThis->xOspiPsvInstance, TRUE );
                if( XST_SUCCESS != iOspiStatus )
                {
                    PLL_ERR( OSPI_NAME, "Error: iFlashSet4bAddrMode failed:%d\r\n", iOspiStatus );
                    INC_ERROR_COUNTER( OSPI_ERRORS_4B_ADDRESS_MODE )
                    iStatus = ERROR;
                }
            }
        }

        if( OK == iStatus )
        {
            if( XOSPIPSV_CONNECTION_MODE_STACKED == pxThis->xOspiPsvInstance.Config.ConnectionMode )
            {
                /* TODO: need to understand why this is * 2*/
                pxFlashConfigTable[ pxThis->ucFctIndex ].ulNumPage   *= 2;
                pxFlashConfigTable[ pxThis->ucFctIndex ].ululNumSect *= 2;

                /* Reset the controller mode to NON-PHY */
                iOspiStatus = XOspiPsv_SetSdrDdrMode( &pxThis->xOspiPsvInstance, XOSPIPSV_EDGE_MODE_SDR_NON_PHY );
                if( XST_SUCCESS != iOspiStatus )
                {
                    PLL_ERR( OSPI_NAME, "Error: XOspiPsv_SetSdrDdrMode failed:%d\r\n", iOspiStatus );
                    INC_ERROR_COUNTER( OSPI_ERRORS_SET_SDR_DDR_MODE )
                    iStatus = ERROR;
                }

                if( OK == iStatus )
                {
                    iOspiStatus = XOspiPsv_SelectFlash( &pxThis->xOspiPsvInstance, XOSPIPSV_SELECT_FLASH_CS1 );
                    if( XST_SUCCESS != iOspiStatus )
                    {
                        PLL_ERR( OSPI_NAME, "Error: XOspiPsv_SelectFlash failed:%d\r\n", iOspiStatus );
                        INC_ERROR_COUNTER( OSPI_ERRORS_SELECT_FLASH )
                        iStatus = ERROR;
                    }
                }

                /* Set Flash device and Controller modes */
                if( OK == iStatus )
                {
                    iOspiStatus = iFlashSetSdrDdrModeEdgeMode( &pxThis->xOspiPsvInstance,
                                                               XOSPIPSV_EDGE_MODE_SDR_NON_PHY );
                    if( XST_SUCCESS != iOspiStatus )
                    {
                        PLL_ERR( OSPI_NAME, "Error: iFlashSetSdrDdrModeEdgeMode failed:%d\r\n", iOspiStatus );
                        INC_ERROR_COUNTER( OSPI_ERRORS_SET_DDR_MODE_INDEX )
                        iStatus = ERROR;
                    }
                }

                if( OK == iStatus )
                {
                    if( pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize > SIXTEENMB )
                    {
                        iOspiStatus = iFlashSet4bAddrMode( &pxThis->xOspiPsvInstance, TRUE );
                        if( XST_SUCCESS != iOspiStatus )
                        {
                            PLL_ERR( OSPI_NAME, "Error: iFlashSet4bAddrMode failed:%d\r\n", iOspiStatus );
                            INC_ERROR_COUNTER( OSPI_ERRORS_4B_ADDRESS_MODE )
                            iStatus = ERROR;
                        }
                    }
                }
            }
        }

        /* Page Size */
        if( OK == iStatus )
        {
            if( pxFlashConfigTable[ pxThis->ucFctIndex ].ulPageSize != pxThis->ulPageSize )
            {
                PLL_ERR( OSPI_NAME,
                         "Error: page size is: %d, expected: %d\r\n",
                         pxFlashConfigTable[ pxThis->ucFctIndex ].ulPageSize,
                         pxThis->ulPageSize );
                INC_ERROR_COUNTER( OSPI_ERRORS_PAGE_SIZE )
                iStatus = ERROR;
            }
        }

        /* Sector Size */
        if( OK == iStatus )
        {
            pxThis->ulOspiSectorSize = pxFlashConfigTable[ pxThis->ucFctIndex ].ulSectSize;
            PLL_LOG( OSPI_NAME,
                     "FCT Index:%d, page size:%d, sector size:%d\r\n",
                     pxThis->ucFctIndex,
                     pxThis->ulPageSize,
                     pxThis->ulOspiSectorSize );
            pxThis->iInitialised = TRUE;
            INC_STAT_COUNTER( OSPI_STATS_INIT_COMPLETED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Function to erase the flash device.
 */
int iOSPI_FlashErase( uint32_t ulAddr, uint32_t ulLength )
{
    int iStatus = ERROR;

    /* TODO: need to add support for flash percentage into erase */
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            int     iOspiStatus = XST_FAILURE;
            uint8_t ucCmdBfr[ OSPI_CMD_BUFFER_SIZE ] =
            {
                0
            };

            INC_STAT_COUNTER( OSPI_STATS_TAKE_MUTEX )

            if( ulAddr & pxThis->ulPageSize )
            {
                PLL_WRN( OSPI_NAME, "Warning: base address is not %d aligned\r\n", ulAddr );
            }

            iOspiStatus = iFlashErase( &pxThis->xOspiPsvInstance, ulAddr, ulLength, ucCmdBfr );
            if( XST_SUCCESS == iOspiStatus )
            {
                iStatus = OK;
                PLL_DBG( OSPI_NAME, "Erased: 0x%x len:%d\r\n", ulAddr, ulLength );
                INC_STAT_COUNTER( OSPI_STATS_ERASE_SUCCESS )
            }
            else
            {
                PLL_ERR( OSPI_NAME, "Error: flash erase failed, ret:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_ERASE_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( OSPI_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Function to read a number of bytes from the flash device.
 */
int iOSPI_FlashRead( uint32_t ulAddr, uint8_t *pucReadBuffer, uint32_t *pulLength )
{
    int iStatus = ERROR;

    /* TODO: need to add support for flash percentage into read */
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucReadBuffer ) &&
        ( NULL != pulLength ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            int iOspiStatus = XST_FAILURE;

            INC_STAT_COUNTER( OSPI_STATS_TAKE_MUTEX )

            pvOSAL_MemSet( pucReadBuffer, 0, *pulLength );
            iOspiStatus = iFlashRead( &pxThis->xOspiPsvInstance, ulAddr, *pulLength, pucReadBuffer );
            if( XST_SUCCESS == iOspiStatus )
            {
                iStatus = OK;
                INC_STAT_COUNTER( OSPI_STATS_READ_SUCCESS )
            }
            else
            {
                PLL_ERR( OSPI_NAME, "Error: flash read failed, ret:%d\r\n", iOspiStatus );
                INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_READ_FAILED )
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( OSPI_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_TAKE_FAILED )
        }

    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Function to write a number of bytes from the flash device.
 */
int iOSPI_FlashWrite( uint32_t ulAddr, uint8_t *pucWriteBuffer, uint32_t ulLength )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucWriteBuffer ) )
    {
        if( OSAL_ERRORS_NONE == iOSAL_Mutex_Take( pxThis->pvOsalMutexHdl,
                                                  OSAL_TIMEOUT_WAIT_FOREVER ) )
        {
            int      iOspiStatus = XST_FAILURE;
            int      iPage       = 0;
            uint32_t ucPageCount = 0;
            uint32_t ucPageSize  = pxThis->ulPageSize;
            pxThis->ucOspiFlashPercentage = 0;

            INC_STAT_COUNTER( OSPI_STATS_TAKE_MUTEX )

            /* Validation */
            ucPageCount = ( ulLength / ucPageSize );
            if( ulLength % ucPageSize )
            {
                ucPageCount++;
                PLL_WRN( OSPI_NAME, "Warning: len:%d is not page:%d aligned\r\n", ulLength, ucPageSize );
            }

            /* Note this used to be the offset as opposed to the address */
            if( ulAddr % ucPageSize )
            {
                PLL_WRN( OSPI_NAME, "Warning: address:%d is not page:%d aligned\r\n", ulAddr, ucPageSize );
            }

            PLL_DBG( OSPI_NAME, "Flashing... page count:%d, page size:%d\r\n", ucPageCount, ucPageSize );

            /* Write first, then read back and verify */
            if( XOSPIPSV_DAC_EN_OPTION == XOspiPsv_GetOptions( &pxThis->xOspiPsvInstance ) )
            {
                PLL_DBG( OSPI_NAME,
                         "WriteCmd: 0x%x\r\n",
                         ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulWriteCmd >> BITSHIFT_1B ) );

                iOspiStatus = iFlashLinearWrite( &pxThis->xOspiPsvInstance,
                                                 ulAddr,
                                                 ( pxFlashConfigTable[ pxThis->ucFctIndex ].ulPageSize * ucPageCount ),
                                                 pucWriteBuffer );
                if( XST_SUCCESS == iOspiStatus )
                {
                    PLL_ERR( OSPI_NAME, "Error: iFlashLinearWrite failed:0x%d\r\n", iOspiStatus );
                    INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_LINEAR_WRITE_FAILED )
                }
                else
                {
                    iStatus = OK;
                }
            }
            else
            {
                uint8_t ucOspiPrevFlashPercentage = 0xff;

                PLL_DBG( OSPI_NAME,
                         "WriteCmd: 0x%x \r\n",
                         ( uint8_t )pxFlashConfigTable[ pxThis->ucFctIndex ].ulWriteCmd );
                for( iPage = 0; iPage < ucPageCount; iPage++ )
                {
                    uint32_t ulWriteOffset = ( iPage * pxFlashConfigTable[ pxThis->ucFctIndex ].ulPageSize );

                    pxThis->ucOspiFlashPercentage = ( iPage * 100 / ucPageCount );
                    /* Only display when its been updated */
                    if( ucOspiPrevFlashPercentage != pxThis->ucOspiFlashPercentage )
                    {
                        PLL_DBG( OSPI_NAME,
                                 "OSPI flashing progress percentage %d%%\r\n",
                                 pxThis->ucOspiFlashPercentage );
                        ucOspiPrevFlashPercentage = pxThis->ucOspiFlashPercentage;
                    }

                    iOspiStatus = iFlashWrite( &pxThis->xOspiPsvInstance,
                                               ulAddr + ulWriteOffset,
                                               ( ( pxFlashConfigTable[ pxThis->ucFctIndex ].ulPageSize ) ),
                                               pucWriteBuffer + ulWriteOffset );
                    if( XST_SUCCESS != iOspiStatus )
                    {
                        PLL_ERR( OSPI_NAME, "Error: write failed: %d\r\n", iOspiStatus );
                        INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_WRITE_FAILED )
                        iStatus = ERROR;
                    }
                    else
                    {
                        iStatus = OK;
                    }
                }
            }

            if( OK == iStatus )
            {
                uint8_t ucReadBuffer[ ucPageSize ] __attribute__ ( ( aligned( OSPI_DATA_ALIGNMENT ) ) );
                int     iCount = 0;
                int     i      = 0;
                int     j      = 0;

                /* read back: check some pages numbers */
                PLL_DBG( OSPI_NAME, "Write complete, read back flash to verify\r\n" );

                pvOSAL_MemSet( ucReadBuffer, 0, sizeof( ucReadBuffer ) );
                for( iCount = 0; iCount < ulLength; iCount += pxThis->ulPageSize )
                {
                    if( ( iCount != 0 ) && ( iCount % ( ucPageCount / 10 ) ) )
                    {
                        continue;
                    }

                    iOspiStatus = iFlashRead( &pxThis->xOspiPsvInstance,
                                              ( ulAddr + iCount ),
                                              pxThis->ulPageSize,
                                              ucReadBuffer );
                    if( XST_SUCCESS != iOspiStatus )
                    {
                        INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_READ_FAILED )
                        PLL_ERR( OSPI_NAME, "Error: iFlashRead() failed:%d\r\n", iOspiStatus );
                        iStatus = ERROR;
                    }

                    if( OK == iStatus )
                    {
                        for( i = 0; i < pxThis->ulPageSize; i++ )
                        {
                            int iMaxIdx = MISMATCH_CHECK_COUNT;
                            if( ( ERROR != *( ( uint32_t * )ucReadBuffer ) ) ||
                                ( iCount + i ) >= ulLength ||
                                ucReadBuffer[ i ] == pucWriteBuffer[ iCount + i ] )
                            {
                                continue;
                            }

                            /*
                             * When mis-match only compare the first MISMATCH_CHECK_COUNT bytes
                             */
                            for( j = 0; j < iMaxIdx; j++ )
                            {
                                PLL_DBG( OSPI_NAME, "%02x ", ucReadBuffer[ j ] );
                            }
                            PLL_DBG( OSPI_NAME, " <= data in ospi\r\n" );
                            for( j = 0; j < iMaxIdx; j++ )
                            {
                                PLL_DBG( OSPI_NAME, "%02x ", pucWriteBuffer[ iCount + j ] );
                            }
                            PLL_DBG( OSPI_NAME, " <= data from pdi\r\n" );

                            PLL_DBG( OSPI_NAME,
                                     "mis-match offset: %d, read 0x%x: pdi 0x%x\r\n",
                                     iCount + i,
                                     ucReadBuffer[ i ],
                                     pucWriteBuffer[ iCount + i ] );

                            INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_READ_MISMATCH )
                            iStatus = ERROR;
                        }
                    }
                }
            }

            if( OK == iStatus )
            {
                INC_STAT_COUNTER( OSPI_STATS_WRITE_SUCCESS )
                pxThis->ucOspiFlashPercentage = 100;
                PLL_DBG( OSPI_NAME, "Flash write complete\r\n" );
            }

            if( OSAL_ERRORS_NONE != iOSAL_Mutex_Release( pxThis->pvOsalMutexHdl ) )
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_RELEASE_FAILED )
                iStatus = ERROR;
            }
            else
            {
                INC_STAT_COUNTER( OSPI_STATS_RELEASE_MUTEX )
            }
        }
        else
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_MUTEX_TAKE_FAILED )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Return the progress of the current operation
 */
int iOSPI_GetOperationProgress( uint8_t *pucPercentage )
{
    int iStatus = ERROR;

    /* Note: not mutex protected as want to return the percentage while operation is in progress */
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pucPercentage ) )
    {
        iStatus        = OK;
        *pucPercentage = pxThis->ucOspiFlashPercentage;
    }

    return iStatus;
}

/**
 * @brief   Print all the stats gathered by the driver
 */
int iOSPI_PrintStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) )
    {
        int i = 0;
        PLL_INF( OSPI_NAME, "============================================================\r\n" );
        PLL_INF( OSPI_NAME, "OSPI Statistics:\n\r" );
        for( i = 0; i < OSPI_STATS_MAX; i++ )
        {
            PRINT_STAT_COUNTER( i );
        }
        PLL_INF( OSPI_NAME, "------------------------------------------------------------\r\n" );
        PLL_INF( OSPI_NAME, "OSPI Errors:\n\r" );
        for( i = 0; i < OSPI_ERRORS_MAX; i++ )
        {
            PRINT_ERROR_COUNTER( i );
        }
        PLL_INF( OSPI_NAME, "============================================================\r\n" );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}

/**
 * @brief   Clear all the stats in the driver
 */
int iOSPI_ClearStatistics( void )
{
    int iStatus = ERROR;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) )
    {
        pvOSAL_MemSet( pxThis->pulStatCounters, 0, sizeof( pxThis->pulStatCounters ) );
        pvOSAL_MemSet( pxThis->pulErrorCounters, 0, sizeof( pxThis->pulErrorCounters ) );
        iStatus = OK;
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iStatus;
}


/******************************************************************************/
/* Private Function implementation                                            */
/******************************************************************************/

/**
 * @brief   Find the FCT index based on the Id read
 */
static int iFindFctIndex( uint32_t ulReadId, uint8_t *pucFctIndex )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pucFctIndex ) )
    {
        uint8_t ucIndex = 0;

        for( ucIndex = 0;
             ucIndex < sizeof( pxFlashConfigTable ) / sizeof( pxFlashConfigTable[ 0 ] );
             ucIndex++ )
        {
            if( pxFlashConfigTable[ ucIndex ].ulJedecId == ulReadId )
            {
                *pucFctIndex = ucIndex;
                iOspiStatus  = XST_SUCCESS;
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Performs a transfer on the bus in polled mode
 */
static int iPollTransferWithRetry( XOspiPsv *pxOspiPsvPtr, XOspiPsv_Msg *pxFlashMsg )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pxFlashMsg ) )
    {
        /*
         * The timer iOSAL_Timer_Start/iOSAL_Timer_Stop functions are very time consuming as this
         * function will be called alot during the flash write. Adding an initial check that the
         * polling has completed, this will be successful nearly all the time and hence won't require
         * starting/stopping the timer but we will keep it for backup to catch any potential failures.
         */
        iOspiStatus = XOspiPsv_PollTransfer( pxOspiPsvPtr, pxFlashMsg );
        if( XST_SUCCESS != iOspiStatus )
        {
            /* Reset abort flag */
            pxThis->iAbortPollWait = FALSE;
            if( OSAL_ERRORS_NONE != iOSAL_Timer_Start( pxThis->pvTimerHandle, OSPI_POLL_OVERALL_TIMEOUT_MS ) )
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_TIMER_START_FAILED )
            }
            else
            {
                int iCount = 0;
                FOREVER
                {
                    iOspiStatus = XOspiPsv_PollTransfer( pxOspiPsvPtr, pxFlashMsg );
                    if( XST_SUCCESS == iOspiStatus || TRUE == pxThis->iAbortPollWait )
                    {
                        /* Break out of loop if success or aborted */
                        break;
                    }

                    PLL_DBG( OSPI_NAME, "polling retry count %d:\r\n", ++iCount );
                    iOSAL_Task_SleepMs( OSPI_POLL_INTERVAL_TIMEOUT_MS );
                }
            }

            /* Stop timer */
            if( OSAL_ERRORS_NONE != iOSAL_Timer_Stop( pxThis->pvTimerHandle ) )
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_TIMER_STOP_FAILED )
                iOspiStatus = XST_FAILURE;
            }
        }


        if( ( XST_SUCCESS != iOspiStatus ) || ( TRUE == pxThis->iAbortPollWait ) )
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_FLASH_POLL_RETRY_FAILED )
            /* Set overall failure to be returned */
            iOspiStatus = XST_FAILURE;
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Reads the flash ID and identifies the flash in FCT table.
 */
static int iFlashReadId( XOspiPsv *pxOspiPsvPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        int      iReadIdBytes = FLASH_ID_READ_SIZE;
        uint32_t ulReadId     = 0;
        char     cflashIDBuf[ FLASH_ID_STR_BUFFER ] =
        {
            0
        };
        char         *pcBufPtr = cflashIDBuf;
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };

        /* Read ID */
        xFlashMsg.Opcode      = READ_ID;
        xFlashMsg.Addrsize    = 0;
        xFlashMsg.Addrvalid   = 0;
        xFlashMsg.TxBfrPtr    = NULL;
        xFlashMsg.RxBfrPtr    = pxThis->ucReadBfrPtr;
        xFlashMsg.ByteCount   = iReadIdBytes;
        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
        xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
        xFlashMsg.IsDDROpCode = 0;
        xFlashMsg.Proto       = 0;
        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
        {
            xFlashMsg.Dummy += XFLASH_OPCODE_DUMMY_CYCLES;
            xFlashMsg.Proto  = XOSPIPSV_READ_8_0_8;
        }

        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        if( XST_SUCCESS == iOspiStatus )
        {
            while( iReadIdBytes >= 0 )
            {
                pcBufPtr += snprintf( pcBufPtr,
                                      FLASH_ID_SPECIFIER_SIZE,
                                      "0x%02X ",
                                      pxThis->ucReadBfrPtr[ xFlashMsg.ByteCount - iReadIdBytes ] );
                iReadIdBytes--;
            }

            PLL_LOG( OSPI_NAME, "FlashID:%s\r\n", cflashIDBuf );

            pxOspiPsvPtr->DeviceIdData = ( ( pxThis->ucReadBfrPtr[ 3 ] << BITSHIFT_3B ) |
                                           ( pxThis->ucReadBfrPtr[ 2 ] << BITSHIFT_2B ) |
                                           ( pxThis->ucReadBfrPtr[ 1 ] << BITSHIFT_1B ) |
                                           pxThis->ucReadBfrPtr[ 0 ] );
            ulReadId = ( ( pxThis->ucReadBfrPtr[ 0 ] << BITSHIFT_2B ) |
                         ( pxThis->ucReadBfrPtr[ 1 ] << BITSHIFT_1B ) |
                         pxThis->ucReadBfrPtr[ 2 ] );

            pxThis->ulFlashMake = pxThis->ucReadBfrPtr[ 0 ];
            iOspiStatus         = iFindFctIndex( ulReadId, &pxThis->ucFctIndex );
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Set the flash DDR mode CT Index
 */
static int iFlashSetSdrDdrModeEdgeMode( XOspiPsv *pxOspiPsvPtr, int iMode )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint8_t ucConfigReg[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };
        uint8_t ucData[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };

        if( XOSPIPSV_EDGE_MODE_DDR_PHY == iMode )
        {
            ucData[ 0 ] = 0xE7;
            ucData[ 1 ] = 0xE7;
        }
        else
        {
            ucData[ 0 ] = 0xFF;
            ucData[ 1 ] = 0xFF;
        }

        xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
        xFlashMsg.Addrsize    = 0;
        xFlashMsg.Addrvalid   = 0;
        xFlashMsg.TxBfrPtr    = NULL;
        xFlashMsg.RxBfrPtr    = NULL;
        xFlashMsg.ByteCount   = 0;
        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
        xFlashMsg.IsDDROpCode = 0;
        xFlashMsg.Proto       = 0;
        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
        {
            xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
        }

        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        if( XST_SUCCESS == iOspiStatus )
        {
            if( XOSPIPSV_DAC_EN_OPTION == pxOspiPsvPtr->OpMode )
            {
                XOspiPsv_ConfigureAutoPolling( pxOspiPsvPtr, iMode );
            }

            xFlashMsg.Opcode      = WRITE_CONFIG_REG;
            xFlashMsg.Addrvalid   = TRUE;
            xFlashMsg.Addrsize    = XFLASH_CMD_ADDRSIZE_3;
            xFlashMsg.Addr        = 0x0;
            xFlashMsg.TxBfrPtr    = ucData;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto     = XOSPIPSV_WRITE_8_8_8;
                xFlashMsg.Addrsize  = XFLASH_CMD_ADDRSIZE_4;
                xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            iOspiStatus = XOspiPsv_SetSdrDdrMode( pxOspiPsvPtr, iMode );
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            /* Read Configuration register */
            xFlashMsg.Opcode      = READ_CONFIG_REG;
            xFlashMsg.Addrsize    = XFLASH_CMD_ADDRSIZE_3;
            xFlashMsg.Addr        = 0x0;
            xFlashMsg.Addrvalid   = TRUE;
            xFlashMsg.TxBfrPtr    = NULL;
            xFlashMsg.RxBfrPtr    = ucConfigReg;
            xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
            xFlashMsg.Dummy       = XFLASH_OPCODE_DUMMY_CYCLES + pxOspiPsvPtr->Extra_DummyCycle;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                /* Read Configuration register */
                xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                xFlashMsg.Proto     = XOSPIPSV_READ_8_8_8;
                xFlashMsg.Addrsize  = XFLASH_CMD_ADDRSIZE_4;
            }
            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            if( ucConfigReg[ 0 ] != ucData[ 0 ] )
            {
                iOspiStatus = XST_FAILURE;
            }
        }

        if( XST_SUCCESS != iOspiStatus )
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_SET_EDGE_MODE )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Set the flash device into 4 byte addressing mode
 */
int iFlashSet4bAddrMode( XOspiPsv *pxOspiPsvPtr, int iEnable )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint8_t ucCommand = 0;
        uint8_t ucFlashStatus[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };

        if( TRUE == iEnable )
        {
            ucCommand = ENTER_4B_ADDR_MODE;
        }
        else
        {
            ucCommand = EXIT_4B_ADDR_MODE;
        }

        xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
        xFlashMsg.Addrsize    = 0;
        xFlashMsg.Addrvalid   = 0;
        xFlashMsg.TxBfrPtr    = NULL;
        xFlashMsg.RxBfrPtr    = NULL;
        xFlashMsg.ByteCount   = 0;
        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
        xFlashMsg.IsDDROpCode = 0;
        xFlashMsg.Proto       = 0;
        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
        {
            xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
        }

        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        if( XST_SUCCESS == iOspiStatus )
        {
            xFlashMsg.Opcode      = ucCommand;
            xFlashMsg.Addrvalid   = 0;
            xFlashMsg.Addrsize    = 0;
            xFlashMsg.TxBfrPtr    = NULL;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = 0;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.Addrsize    = XFLASH_CMD_ADDRSIZE_3;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            FOREVER
            {
                xFlashMsg.Opcode      = pxFlashConfigTable[ pxThis->ucFctIndex ].ucStatusCmd;
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = ucFlashStatus;
                xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
                xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto     = XOSPIPSV_READ_8_0_8;
                    xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                    xFlashMsg.Dummy    += XFLASH_OPCODE_DUMMY_CYCLES;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                if( XST_SUCCESS != iOspiStatus )
                {
                    break;
                }

                if( ( 0 != ( ucFlashStatus[ 0 ] & XFLASH_STATUS_BYTE ) ) )
                {
                    break;
                }
            }
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            switch( pxThis->ulFlashMake )
            {
            case MICRON_OCTAL_ID_BYTE0:
            {
                xFlashMsg.Opcode      = WRITE_DISABLE_CMD;
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = NULL;
                xFlashMsg.ByteCount   = 0;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                break;
            }

            default:
            {
                PLL_ERR( OSPI_NAME,
                         "Error: current implementation only supports Mircon flash part, found 0x%x\r\n",
                         pxThis->ulFlashMake );
                iOspiStatus = XST_FAILURE;
                break;
            }
            }
        }

        if( XST_SUCCESS != iOspiStatus )
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_SET_4B_ADDR_MODE )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   This functions translates the address based on the type of interconnection
 */
static int iGetRealAddr( XOspiPsv *pxOspiPsvPtr, uint32_t ulAddress, uint32_t *pulRealAddress )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pulRealAddress ) )
    {
        uint8_t ucChipSel = XOSPIPSV_SELECT_FLASH_CS0;

        *pulRealAddress = ulAddress;

        if( ( XOSPIPSV_CONNECTION_MODE_STACKED == pxOspiPsvPtr->Config.ConnectionMode ) &&
            ( ulAddress & pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize ) )
        {
            ucChipSel       = XOSPIPSV_SELECT_FLASH_CS1;
            *pulRealAddress = ulAddress & ( ~pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize );
        }

        iOspiStatus = XOspiPsv_SelectFlash( pxOspiPsvPtr, ucChipSel );
        if( XST_FAILURE == iOspiStatus )
        {
            INC_ERROR_COUNTER( OSPI_ERRORS_SELECT_FLASH )
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Determine the number of lines used for command, address and data
 */
static int iGetProtoType( XOspiPsv *pxOspiPsvPtr, int iRead, uint8_t *pucNum )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        if( TRUE == iRead )
        {
            *pucNum = XOSPIPSV_READ_1_8_8;
        }
        else
        {
            if( XOSPIPSV_IDAC_MODE == pxOspiPsvPtr->OpMode )
            {
                *pucNum = XOSPIPSV_WRITE_1_1_1;
            }
            else
            {
                *pucNum = XOSPIPSV_WRITE_1_1_8;
            }
        }

        iOspiStatus = XST_SUCCESS;
    }

    return iOspiStatus;
}

/**
 * @brief   This function erases the sectors in the serial Flash connected to the
 *          OSPIPSV interface
 */
static int iFlashErase( XOspiPsv *pxOspiPsvPtr,
                        uint32_t ulAddress,
                        uint32_t ulByteCount,
                        uint8_t *pucWriteBfrPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pucWriteBfrPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        int      iSector   = 0;
        uint32_t ulNumSect = 0;
        uint8_t  ucFlashStatus[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };
        uint32_t ulRealAddr = 0;

        /*
         * If erase size is same as the total size of the flash, use bulk erase
         * command or die erase command multiple times as required
         */
        if( ulByteCount == ( pxFlashConfigTable[ pxThis->ucFctIndex ].ululNumSect *
                             pxFlashConfigTable[ pxThis->ucFctIndex ].ulSectSize ) )
        {
            if( XOSPIPSV_CONNECTION_MODE_STACKED == pxOspiPsvPtr->Config.ConnectionMode )
            {
                iOspiStatus = XOspiPsv_SelectFlash( pxOspiPsvPtr, XOSPIPSV_SELECT_FLASH_CS0 );
            }

            if( XST_SUCCESS == iOspiStatus )
            {
                if( 1 == pxFlashConfigTable[ pxThis->ucFctIndex ].ucNumDie )
                {
                    /* Call Bulk erase */
                    PLL_DBG( OSPI_NAME,
                             "Bulk EraseCmd: 0x%x\r\n",
                             ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >> BITSHIFT_1B ) );
                    iBulkErase( pxOspiPsvPtr );
                }

                if( pxFlashConfigTable[ pxThis->ucFctIndex ].ucNumDie > 1 )
                {
                    /* Call Die erase */
                    PLL_DBG( OSPI_NAME,
                             "Die EraseCmd: 0x%x\r\n",
                             ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >> BITSHIFT_2B ) );
                    iDieErase( pxOspiPsvPtr );
                }

                if( XOSPIPSV_CONNECTION_MODE_STACKED == pxOspiPsvPtr->Config.ConnectionMode )
                {
                    iOspiStatus = XOspiPsv_SelectFlash( pxOspiPsvPtr, XOSPIPSV_SELECT_FLASH_CS1 );
                    if( XST_SUCCESS == iOspiStatus )
                    {
                        if( 1 == pxFlashConfigTable[ pxThis->ucFctIndex ].ucNumDie )
                        {
                            /* Call Bulk erase */
                            PLL_DBG( OSPI_NAME,
                                     "Bulk EraseCmd 0x%x\r\n",
                                     ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >>
                                                  BITSHIFT_1B ) );
                            iBulkErase( pxOspiPsvPtr );
                        }

                        if( pxFlashConfigTable[ pxThis->ucFctIndex ].ucNumDie > 1 )
                        {
                            /* Call Die erase */
                            PLL_DBG( OSPI_NAME,
                                     "Die EraseCmd 0x%x\r\n",
                                     ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >>
                                                  BITSHIFT_2B ) );
                            iDieErase( pxOspiPsvPtr );
                        }
                    }
                    else
                    {
                        INC_ERROR_COUNTER( OSPI_ERRORS_SELECT_FLASH )
                    }
                }
            }
            else
            {
                INC_ERROR_COUNTER( OSPI_ERRORS_SELECT_FLASH )
            }
        }
        else
        {
            PLL_DBG( OSPI_NAME, "EraseCmd 0x%x\r\n", ( uint8_t )pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd );

            /*
             * If the erase size is less than the total size of the flash, use
             * sector erase command
             */

            /*
             * Calculate no. of sectors to erase based on byte count
             */
            ulNumSect = ulByteCount / ( pxFlashConfigTable[ pxThis->ucFctIndex ].ulSectSize );
            if( 0 != ( ulByteCount % ( pxFlashConfigTable[ pxThis->ucFctIndex ].ulSectSize ) ) )
            {
                ulNumSect += 1;
            }

            for( iSector = 0; iSector < ulNumSect; iSector++ )
            {
                /*
                 * Translate address based on type of connection
                 * If stacked assert the slave select based on address
                 */
                iOspiStatus = iGetRealAddr( pxOspiPsvPtr, ulAddress, &ulRealAddr );
                if( XST_SUCCESS != iOspiStatus )
                {
                    PLL_ERR( OSPI_NAME, "Error: iGetRealAddr failed: %d\r\n", iOspiStatus );
                    break;
                }

                /*
                 * Send the write enable command to the Flash so that it can be
                 * written to, this needs to be sent as a separate transfer before
                 * the write
                 */

                xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = NULL;
                xFlashMsg.ByteCount   = 0;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                xFlashMsg.Dummy       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                if( XST_SUCCESS == iOspiStatus )
                {
                    xFlashMsg.Opcode      = ( uint8_t )pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd;
                    xFlashMsg.Addrsize    = XFLASH_CMD_ADDRSIZE_4;
                    xFlashMsg.Addrvalid   = TRUE;
                    xFlashMsg.TxBfrPtr    = NULL;
                    xFlashMsg.RxBfrPtr    = NULL;
                    xFlashMsg.ByteCount   = 0;
                    xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
                    xFlashMsg.Addr        = ulRealAddr;
                    xFlashMsg.IsDDROpCode = 0;
                    xFlashMsg.Proto       = 0;
                    xFlashMsg.Dummy       = 0;
                    if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                    {
                        xFlashMsg.Proto = XOSPIPSV_WRITE_8_8_0;
                    }
                    iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                }

                if( XST_SUCCESS == iOspiStatus )
                {
                    FOREVER
                    {
                        xFlashMsg.Opcode      = pxFlashConfigTable[ pxThis->ucFctIndex ].ucStatusCmd;
                        xFlashMsg.Addrsize    = 0;
                        xFlashMsg.Addrvalid   = 0;
                        xFlashMsg.TxBfrPtr    = NULL;
                        xFlashMsg.RxBfrPtr    = ucFlashStatus;
                        xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
                        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
                        xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
                        xFlashMsg.IsDDROpCode = 0;
                        xFlashMsg.Proto       = 0;
                        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                        {
                            xFlashMsg.Proto     = XOSPIPSV_READ_8_0_8;
                            xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                            xFlashMsg.Dummy    += XFLASH_OPCODE_DUMMY_CYCLES;
                        }

                        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                        if( XST_SUCCESS != iOspiStatus )
                        {
                            break;
                        }

                        if( ( 0 != ( ucFlashStatus[ 0 ] & XFLASH_STATUS_BYTE ) ) )
                        {
                            break;
                        }
                    }

                    ulAddress += pxFlashConfigTable[ pxThis->ucFctIndex ].ulSectSize;
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Writes to the serial Flash connected to the OSPIPSV interface
 */
static int iFlashWrite( XOspiPsv *pxOspiPsvPtr,
                        uint32_t ulAddress,
                        uint32_t ulByteCount,
                        uint8_t *pucWriteBfrPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pucWriteBfrPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint8_t ucFlashStatus[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };
        uint32_t ulBytesToWrite = 0;
        uint32_t ulRealAddr     = 0;
        uint8_t  ucNumLines     = 0;

        while( 0 != ulByteCount )
        {
            /*
             * Translate address based on type of connection
             * If stacked assert the slave select based on address
             */
            iOspiStatus = iGetRealAddr( pxOspiPsvPtr, ulAddress, &ulRealAddr );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iGetRealAddr failed: %d\r\n", iOspiStatus );
                break;
            }

            xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
            xFlashMsg.Addrsize    = 0;
            xFlashMsg.Addrvalid   = 0;
            xFlashMsg.TxBfrPtr    = NULL;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = 0;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            xFlashMsg.Dummy       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: poll transfer failed: %d\r\n", iOspiStatus );
                break;
            }

            /* Each write is 8 bytes in length or less */
            if( ulByteCount <= FLASH_WRITE_BYTE_SIZE )
            {
                ulBytesToWrite = ulByteCount;
                ulByteCount    = 0;
            }
            else
            {
                ulBytesToWrite = FLASH_WRITE_BYTE_SIZE;
                ulByteCount   -= FLASH_WRITE_BYTE_SIZE;
            }

            iOspiStatus = iGetProtoType( pxOspiPsvPtr, FALSE, &ucNumLines );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iGetProtoType failed: %d\r\n", iOspiStatus );
                break;
            }

            xFlashMsg.Opcode      = ( uint8_t )pxFlashConfigTable[ pxThis->ucFctIndex ].ulWriteCmd;
            xFlashMsg.Addrvalid   = TRUE;
            xFlashMsg.TxBfrPtr    = pucWriteBfrPtr;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = ulBytesToWrite;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.Proto       = ucNumLines;
            xFlashMsg.Dummy       = 0;
            xFlashMsg.Addrsize    = XFLASH_CMD_ADDRSIZE_4;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Addr        = ulRealAddr;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_WRITE_8_8_8;
            }
            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: poll transfer failed: %d\r\n", iOspiStatus );
                break;
            }

            pucWriteBfrPtr += FLASH_WRITE_BYTE_SIZE;
            ulAddress      += FLASH_WRITE_BYTE_SIZE;

            FOREVER
            {
                xFlashMsg.Opcode      = pxFlashConfigTable[ pxThis->ucFctIndex ].ucStatusCmd;
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = ucFlashStatus;
                xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
                xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto     = XOSPIPSV_READ_8_0_8;
                    xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                    xFlashMsg.Dummy    += XFLASH_OPCODE_DUMMY_CYCLES;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                if( XST_SUCCESS != iOspiStatus )
                {
                    PLL_ERR( OSPI_NAME, "Error: poll transfer failed: %d\r\n", iOspiStatus );
                    break;
                }

                if( ( 0 != ( ucFlashStatus[ 0 ] & XFLASH_STATUS_BYTE ) ) )
                {
                    break;
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Writes to the serial Flash connected to the OSPIPSV interface
 */
static int iFlashLinearWrite( XOspiPsv *pxOspiPsvPtr,
                              uint32_t ulAddress,
                              uint32_t ulByteCount,
                              uint8_t *pucWriteBfrPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pucWriteBfrPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };

        xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
        xFlashMsg.Addrsize    = 0;
        xFlashMsg.Addrvalid   = 0;
        xFlashMsg.TxBfrPtr    = NULL;
        xFlashMsg.RxBfrPtr    = NULL;
        xFlashMsg.ByteCount   = 0;
        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
        xFlashMsg.IsDDROpCode = 0;
        xFlashMsg.Proto       = 0;
        xFlashMsg.Dummy       = 0;
        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
        {
            xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
        }

        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        if( XST_SUCCESS == iOspiStatus )
        {
            uint8_t ucNumLines = 0;

            iOspiStatus = iGetProtoType( pxOspiPsvPtr, FALSE, &ucNumLines );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iGetProtoType failed: %d\r\n", iOspiStatus );
            }
            else
            {
                xFlashMsg.Opcode    = ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulWriteCmd >> BITSHIFT_1B );
                xFlashMsg.Addrvalid = TRUE;
                xFlashMsg.TxBfrPtr  = pucWriteBfrPtr;
                xFlashMsg.RxBfrPtr  = NULL;
                xFlashMsg.ByteCount = ulByteCount;
                xFlashMsg.Flags     = XOSPIPSV_MSG_FLAG_TX;
                xFlashMsg.Addrsize  = XFLASH_CMD_ADDRSIZE_4;
                xFlashMsg.Addr      = ulAddress;
                xFlashMsg.Proto     = ucNumLines;
                xFlashMsg.Dummy     = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto = XOSPIPSV_WRITE_8_8_8;
                }
                xFlashMsg.IsDDROpCode = 0;
                iOspiStatus           = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   This function performs the read
 */
static int iFlashRead( XOspiPsv *pxOspiPsvPtr,
                       uint32_t ulAddress,
                       uint32_t ulByteCount,
                       uint8_t *pucReadBfrPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) &&
        ( NULL != pucReadBfrPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint32_t ulRealAddr       = 0;
        uint32_t ulBytesToRead    = 0;
        uint8_t  ucNumLines       = 0;
        int      iUnalignedRead   = FALSE;                                     /* Read buffer required to be on 8 byte boundary */
        uint32_t ucReadIterations = 1;                                         /* At least one read required when aligned */
        int      i                = 0;

        if( ( ulAddress < pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize ) &&
            ( ( ulAddress + ulByteCount ) >= pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize ) &&
            ( XOSPIPSV_CONNECTION_MODE_STACKED == pxOspiPsvPtr->Config.ConnectionMode ) )
        {
            ulBytesToRead = ( pxFlashConfigTable[ pxThis->ucFctIndex ].ulFlashDeviceSize - ulAddress );
        }
        else
        {
            ulBytesToRead = ulByteCount;
        }

        if( 0 != ( ulBytesToRead % OSPI_READ_BUFFER_ALIGNMENT ) )
        {
            /* Unaligned read found, use internal buffer to read over a number of iterations */
            if( OSPI_READ_BUFFER_SIZE < ulBytesToRead )
            {
                ucReadIterations = ( ( ulBytesToRead / OSPI_READ_BUFFER_SIZE ) + 1 );
            }
            iUnalignedRead = TRUE;
            ulBytesToRead  = OSPI_READ_BUFFER_SIZE;
        }

        for( i = 0; i < ucReadIterations; i++ )
        {
            /*
             * Translate address based on type of connection
             * If stacked assert the slave select based on address
             */
            iOspiStatus = iGetRealAddr( pxOspiPsvPtr, ulAddress, &ulRealAddr );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iGetRealAddr failed: %d\r\n", iOspiStatus );
                break;
            }

            iOspiStatus = iGetProtoType( pxOspiPsvPtr, TRUE, &ucNumLines );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: iGetProtoType failed: %d\r\n", iOspiStatus );
                break;
            }

            xFlashMsg.Opcode    = ( uint8_t )pxFlashConfigTable[ pxThis->ucFctIndex ].ulReadCmd;
            xFlashMsg.Addrsize  = XFLASH_CMD_ADDRSIZE_4;
            xFlashMsg.Addrvalid = TRUE;
            xFlashMsg.TxBfrPtr  = NULL;
            if( FALSE == iUnalignedRead )
            {
                /* Normal aligned mode just read into buffer provided */
                xFlashMsg.RxBfrPtr = pucReadBfrPtr;
            }
            else
            {
                /* Read into internal 8 byte aligned buffer */
                xFlashMsg.RxBfrPtr = pxThis->ucReadBfrPtr;
            }
            xFlashMsg.ByteCount = ulBytesToRead;
            xFlashMsg.Flags     = XOSPIPSV_MSG_FLAG_RX;
            xFlashMsg.Addr      = ulRealAddr;
            xFlashMsg.Proto     = ucNumLines;
            xFlashMsg.Dummy     = pxFlashConfigTable[ pxThis->ucFctIndex ].ucDummyCycles +
                                  pxOspiPsvPtr->Extra_DummyCycle;
            xFlashMsg.IsDDROpCode = 0;

            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_READ_8_8_8;
                xFlashMsg.Dummy = ( XFLASH_OPCODE_DUMMY_CYCLES + XFLASH_OPCODE_DUMMY_CYCLES ) +
                                  pxOspiPsvPtr->Extra_DummyCycle;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            if( XST_SUCCESS != iOspiStatus )
            {
                PLL_ERR( OSPI_NAME, "Error: flash Read fail: %d\r\n", iOspiStatus );
                break;
            }
            else
            {
                if( TRUE == iUnalignedRead )
                {
                    /* Copy the data into the return buffer */
                    pvOSAL_MemCpy( &pucReadBfrPtr[ i * OSPI_READ_BUFFER_SIZE ], pxThis->ucReadBfrPtr, ulBytesToRead );

                    /* Move the next base address forward */
                    ulAddress += OSPI_READ_BUFFER_SIZE;
                    if( ( ucReadIterations - 1 ) == i )
                    {
                        /* Final iteration will be less than OSPI_READ_BUFFER_SIZE */
                        ulBytesToRead = ( ulByteCount % OSPI_READ_BUFFER_SIZE );
                    }
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   This functions performs a bulk erase operation when the
 *          flash device has a single die
 */
static int iBulkErase( XOspiPsv *pxOspiPsvPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint8_t ucFlashStatus[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };

        xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
        xFlashMsg.Addrsize    = 0;
        xFlashMsg.Addrvalid   = 0;
        xFlashMsg.TxBfrPtr    = NULL;
        xFlashMsg.RxBfrPtr    = NULL;
        xFlashMsg.ByteCount   = 0;
        xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
        xFlashMsg.IsDDROpCode = 0;
        xFlashMsg.Proto       = 0;
        xFlashMsg.Dummy       = 0;
        if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
        {
            xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
        }

        iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        if( XST_SUCCESS == iOspiStatus )
        {
            /*
             * Send the write enable command to the Flash so that it can be
             * written to, this needs to be sent as a separate transfer before
             * the write
             */
            xFlashMsg.Opcode      = ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >> BITSHIFT_1B );
            xFlashMsg.Addrsize    = 0;
            xFlashMsg.Addrvalid   = 0;
            xFlashMsg.TxBfrPtr    = NULL;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = 0;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            xFlashMsg.Dummy       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
        }

        if( XST_SUCCESS == iOspiStatus )
        {
            FOREVER
            {
                xFlashMsg.Opcode      = pxFlashConfigTable[ pxThis->ucFctIndex ].ucStatusCmd;
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = ucFlashStatus;
                xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
                xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto     = XOSPIPSV_READ_8_0_8;
                    xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                    xFlashMsg.Dummy    += XFLASH_OPCODE_DUMMY_CYCLES;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                if( XST_SUCCESS != iOspiStatus )
                {
                    break;
                }

                if( ( 0 != ( ucFlashStatus[ 0 ] & XFLASH_STATUS_BYTE ) ) )
                {
                    break;
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   This functions performs a bulk erase operation when the
 *          flash device has a single die
 */
static int iDieErase( XOspiPsv *pxOspiPsvPtr )
{
    int iOspiStatus = XST_FAILURE;

    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pxOspiPsvPtr ) )
    {
        XOspiPsv_Msg xFlashMsg =
        {
            0
        };
        uint8_t ucDieCnt = 0;
        uint8_t ucFlashStatus[ OSPI_STATUS_BUFFER_SIZE ] __attribute__ ( ( aligned( OSPI_WRITE_BUFFER_ALIGNMENT ) ) ) =
        {
            0
        };

        for( ucDieCnt = 0; ucDieCnt < pxFlashConfigTable[ pxThis->ucFctIndex ].ucNumDie; ucDieCnt++ )
        {
            /*
             * Send the write enable command to the Flash so that it can be
             * written to, this needs to be sent as a separate transfer before
             * the write
             */
            xFlashMsg.Opcode      = WRITE_ENABLE_CMD;
            xFlashMsg.Addrsize    = 0;
            xFlashMsg.Addrvalid   = 0;
            xFlashMsg.TxBfrPtr    = NULL;
            xFlashMsg.RxBfrPtr    = NULL;
            xFlashMsg.ByteCount   = 0;
            xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
            xFlashMsg.IsDDROpCode = 0;
            xFlashMsg.Proto       = 0;
            xFlashMsg.Dummy       = 0;
            if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
            {
                xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
            }

            iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            if( XST_SUCCESS == iOspiStatus )
            {
                xFlashMsg.Opcode = ( uint8_t )( pxFlashConfigTable[ pxThis->ucFctIndex ].ulEraseCmd >>
                                                BITSHIFT_2B );
                xFlashMsg.Addrsize    = 0;
                xFlashMsg.Addrvalid   = 0;
                xFlashMsg.TxBfrPtr    = NULL;
                xFlashMsg.RxBfrPtr    = NULL;
                xFlashMsg.ByteCount   = 0;
                xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_TX;
                xFlashMsg.IsDDROpCode = 0;
                xFlashMsg.Proto       = 0;
                xFlashMsg.Dummy       = 0;
                if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                {
                    xFlashMsg.Proto = XOSPIPSV_WRITE_8_0_0;
                }

                iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
            }

            if( XST_SUCCESS == iOspiStatus )
            {
                FOREVER
                {
                    xFlashMsg.Opcode      = pxFlashConfigTable[ pxThis->ucFctIndex ].ucStatusCmd;
                    xFlashMsg.Addrsize    = 0;
                    xFlashMsg.Addrvalid   = 0;
                    xFlashMsg.TxBfrPtr    = NULL;
                    xFlashMsg.RxBfrPtr    = ucFlashStatus;
                    xFlashMsg.ByteCount   = XFLASH_BYTE_COUNT_1;
                    xFlashMsg.Flags       = XOSPIPSV_MSG_FLAG_RX;
                    xFlashMsg.Dummy       = pxOspiPsvPtr->Extra_DummyCycle;
                    xFlashMsg.IsDDROpCode = 0;
                    xFlashMsg.Proto       = 0;
                    if( XOSPIPSV_EDGE_MODE_DDR_PHY == pxOspiPsvPtr->SdrDdrMode )
                    {
                        xFlashMsg.Proto     = XOSPIPSV_READ_8_0_8;
                        xFlashMsg.ByteCount = XFLASH_BYTE_COUNT_2;
                        xFlashMsg.Dummy    += XFLASH_OPCODE_DUMMY_CYCLES;
                    }

                    iOspiStatus = iPollTransferWithRetry( pxOspiPsvPtr, &xFlashMsg );
                    if( iOspiStatus != XST_SUCCESS )
                    {
                        break;
                    }

                    if( ( 0 != ( ucFlashStatus[ 0 ] & XFLASH_STATUS_BYTE ) ) )
                    {
                        break;
                    }
                }
            }
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }

    return iOspiStatus;
}

/**
 * @brief   Callback invoked whenever polling interval has been exceeded
 */
static void vTimerPollTimeoutCb( void *pvTimerHandle )
{
    if( ( UPPER_FIREWALL == pxThis->ulUpperFirewall ) &&
        ( LOWER_FIREWALL == pxThis->ulLowerFirewall ) &&
        ( TRUE == pxThis->iInitialised ) &&
        ( NULL != pvTimerHandle ) )
    {
        if( pxThis->pvTimerHandle == pvTimerHandle )
        {
            pxThis->iAbortPollWait = TRUE;
        }
    }
    else
    {
        INC_ERROR_COUNTER( OSPI_ERRORS_VALIDAION_FAILED )
    }
}
