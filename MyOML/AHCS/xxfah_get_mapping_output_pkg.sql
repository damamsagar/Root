create or replace PACKAGE BODY      XXFAH_GET_MAPPING_OUTPUT_PKG
AS
/*
||   Filename: XXFAH_GET_MAPPING_OUTPUT_PKG.pkb
||   Description: This package is to get Mapping Output values
||                for different Source system segments like
||                ILSA Millie Account value, ILNA Account value,
||                ILNA Cost Centre,GS Millie Cost centre,
||                GS Millie Account,GS Millie Related Party etc.,
||                for CORP, ACCOUNT, CCENTRE.
|| -------------------------------------------------------------
||   Ver  Date              Author                Modification
|| -------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan           Initial version
||   1.1  02-Nov-11        Kalaiselvan           Incorporated Review Comments
||   1.2  15-Feb-12        Swathi                Implemented fusion changes
||   1.3  13-Jun-12        Swathi                Defect 670 - Modified GsMillyAccountValue procedure
||   1.4  27-Feb-13        Swathi                Enhancement request for Oracle layouts
||   1.5  01-Apr-14        Karin Roux            0023763 - Control Accounts in Fusion FAH
||   1.6  25-May-15        Karin Roux            0023963 - Nigeria
||   1.7  27-JUN-16        Leila Stotter         0026223  -Elective Move-  CS - Alignment with Oracle Tax Fund
||   1.8  28-JUL-16        Leila Stotter         0026224 -Elective Move-  RMM   -Alignment with Oracle Tax Fund
||   2.0  17-FEB-17        Leila van Diggele     Proj 0026815 - Oracle EBS GL Project
||   2.1 19-FEB-19        Leila van Diggele      0030446_1497732_FAH_Milly_RMM_Product_to_TaxFund_Mapping
||   3.0 03-JUNE-21       Vishal Choithwani      Validate segment mapiing against value set for ccid segments
|| -------------------------------------------------------------
||
||   All rights reserved.
*/

/*=========================================================================+
   | Procedure: GetSegmentValues
   +--------------------------------------------------------------------------+
   | Description: This procedure is used to check segment value available in valueset or not.
   +--------------------------------------------------------------------------+
   | Parameters: i_segmentvalue  - segment value that need to check in value sets
   |             i_segment_category    - Application ID to fetch the period open days
   |             
   +--------------------------------------------------------------------------+
   | This function addition is part of CR-404
   +--------------------------------------------------------------------------+
   | History:
   | Author       |     Date   | Version | Description
   +--------------------------------------------------------------------------+
   | Vishal Choithwani | 03-06-2021 |   1.0   | Initial Version
   | 
   +==========================================================================*/
   PROCEDURE GetSegmentValues(i_segmentvalue   IN XXFAH_PASSTHROUGH_LINES.segment1%TYPE,
                         i_segment_category    IN XXAGIS_VALUE_SET_VALUES.VALUE_CATEGORY%TYPE,
                         o_status     OUT BOOLEAN)
   AS
     l_error_msg          VARCHAR2(2000);
     l_value   VARCHAR2(10);

   -- Checking segment values in SaaS VALUE_SET_VALUES
BEGIN

      o_status         := TRUE;
      
    IF i_segmentvalue in('0','00','000','0000','00000','000000','0000000','00000000')
    
      THEN
     
       o_status         := TRUE;  

      
      ELSE
	  
       select FLEX_VALUE
      into   l_value
      from   XXAGIS_VALUE_SET_VALUES s
      where  S.VALUE_CATEGORY = i_segment_category
      and    s.FLEX_VALUE = i_segmentvalue
	  AND enabled_flag = 'Y'
       AND TRUNC(SYSDATE) BETWEEN TRUNC(NVL(start_date_active,SYSDATE))
                       AND TRUNC(NVL(end_date_active,SYSDATE));



      -- If Period status open or future then send the TRUE status to caller.
      IF l_value is not null
      THEN
     
       o_status         := TRUE;  

      
      ELSE
	  
       o_status         := FALSE;  
       
    END IF;  
       
    END IF;   

     
   EXCEPTION
      WHEN OTHERS
      THEN
         l_error_msg := 'GetSegmentValues SQLERRM: '||SQLERRM;
         o_status := FALSE; -- To Mark the header as Error.
		 
   END GetSegmentValues;



FUNCTION GsMillyBudgetCentreValue ( i_corp      IN   VARCHAR2,
                                    i_account   IN   VARCHAR2,
                                    i_ccentre   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: GsMillyBudgetCentreValue
||   Description: This Function GsMillyBudgetCentreValue is to
||		  Return GS Milly Cost Centre Mapping Output value for
||                CORP, Account and Cost Centre values of GS MILLY by
||                mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the GS MILLY
|| i_account              ---  Account value of the GS MILLY
|| i_ccentre              ---  Cost Centre Value of the GS MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_ccentre   VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_ccentre              VARCHAR2 (100);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_RMM_BUDGET_CENTRE_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_RMM_BUDGET_CENTRE';
  l_err_msg              VARCHAR2(2000);

BEGIN
  BEGIN
    l_corp_accnt_ccentre :=  (i_corp || '.' || i_account || '.' || i_ccentre);
    l_ccentre            :=  (i_ccentre);

    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt_ccentre;  --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_ccentre;  --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
         --- RETURN l_ccentre; OC_Comment
          RAISE;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in GsMillyBudgetCentreValue (Fn)-GsMillyBudgetCentreValue:'|| l_err_msg);      OC_Comment
    RAISE;
END GsMillyBudgetCentreValue;


FUNCTION GsMillyAccountValue ( i_corp      IN   VARCHAR2,
                               i_account   IN   VARCHAR2,
                               i_ccentre   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: GsMillyAccountValue
||   Description: This Function GsMillyAccountValue is to Return GS Milly Account Mapping Output value for
||                CORP, Account and Cost Centre values of GS MILLY by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of GS MILLIY
|| i_account              ---  Account value of GS MILLIY
|| i_ccentre              ---  Cost Centre Value of GS MILLIY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_ccentre   VARCHAR2 (100);
  l_accnt_ccentre        VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_account              VARCHAR2 (50);
  l_ccentre              VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_RMM_ACCOUNT_DEV2';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_RMM_ACCOUNT_DEV1';
  l_mapping_set_code2    VARCHAR2 (50) := 'FAH_MIL_RMM_ACCOUNT';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_account || '.' || i_ccentre);
  l_accnt_ccentre      :=  (i_account || '.' || i_ccentre);
  l_account            :=  (i_account);
  l_ccentre            :=  (i_ccentre);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_accnt_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_accnt_ccentre; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --AND    input_value_constant1 = l_ccentre; -- commented as per defect 670-input value has to be milly account.
            --v2.0 AND    input_value_constant1 = l_account;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_account; --v2.0

            RETURN l_output_value;
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
            --  RETURN l_account;  OC_Comment
          RAISE;
          END;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
   -- fnd_file.put_line (fnd_file.log,'Error in GsMillyAccountValue (Fn)-GS MILLY ACCOUNT:' || l_err_msg);   OC_Comment
    RAISE;
END GsMillyAccountValue;

FUNCTION GsMillyRelatedPartyValue ( i_corp      IN   VARCHAR2,
                                    i_account   IN   VARCHAR2,
                                    i_ccentre   IN   VARCHAR2 )
RETURN VARCHAR2
AS
/*
||   Function: GsMillyRelatedPartyValue
||   Description: This Function GsMillyRelatedPartyValue is to Return GS Milly Related Mapping Output value for
||                CORP, Account and Cost Centre values of GS MILLY by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of GS MILLIY
|| i_account              ---  Account value of GS MILLIY
|| i_ccentre              ---  Cost Centre Value of GS MILLIY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_ccentre   VARCHAR2 (100);
  l_corp_accnt           VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (20) := '0000';
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_RMM_RELATED_PARTY_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_RELATED_PARTY';
  l_err_msg              VARCHAR2(2000);

BEGIN
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_account || '.' || i_ccentre);
  l_corp_accnt         :=  (i_corp || '.' || i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- v2.0 commented out as xla_mapping_set_flavors does not exist in EBS R12
--          SELECT default_constant
--          INTO   l_default_output
--          FROM   xla_mapping_set_flavors
--          WHERE  mapping_set_code = l_mapping_set_code1;

            ----v2.0
            SELECT value_constant
            INTO   l_default_output
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            AND    input_value_type_code = 'D';
            ----v2.0

            l_output_value := l_default_output;
            RETURN l_output_value;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in GsMillyRelatedPartyValue (Fn)-GS MILLIE RELATED PARTY'|| l_err_msg);   OC_Comment
    RAISE;
END GsMillyRelatedPartyValue;

FUNCTION GsMillyProductValue ( i_corp      IN   VARCHAR2,
                               i_account   IN   VARCHAR2,
                               i_ccentre   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: GsMillyProductValue
||   Description: This function GsMillyProductValue is to Return GS Milly Product Mapping Output value for
||                CORP, Account and Cost Centre values of GS Milly Product Value by mapping with the Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the GS MILLY
|| i_account              ---  Account value of the GS MILLY
|| i_ccentre              ---  Cost Centre Value of the GS MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_ccentre   VARCHAR2 (100);
  l_accnt_ccentre        VARCHAR2 (100);
  l_ccentre              VARCHAR2 (50);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (20) := '00000';
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_RMM_PRODUCT_DEV2';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_RMM_PRODUCT_DEV1';
  l_mapping_set_code2    VARCHAR2 (50) := 'FAH_MIL_RMM_PRODUCT';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_account || '.' || i_ccentre);
  l_accnt_ccentre      :=  (i_account || '.' || i_ccentre);
  l_ccentre            :=  (i_ccentre);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_Code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_accnt_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_accnt_ccentre; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_ccentre;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_ccentre;  --v2.0

            RETURN l_output_value;
          EXCEPTION
            WHEN NO_DATA_FOUND THEN
                --v2.0 commented out because xla_mapping_set_flavors does not exist in EBS R12
--              SELECT default_constant
--              INTO   l_default_output
--              FROM   xla_mapping_set_flavors
--              WHERE  mapping_set_code = l_mapping_set_code2;

                ----v2.0
                SELECT value_constant
                INTO   l_default_output
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code2
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                AND    input_value_type_code = 'D';
                ----v2.0

                l_output_value := l_default_output;
                RETURN l_output_value;
          END;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log, 'Error in GsMillyProductValue (Fn)-GsMillyProductValue:'|| l_err_msg);   OC_Comment
    RAISE;
END GsMillyProductValue;

FUNCTION GsMillyTaxFundValue ( i_corp      IN   VARCHAR2,
                               i_member    IN   VARCHAR2,
                               i_product   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: GsMillyTaxFundValue
||   Description: This function GsMillyTaxFundValue is to Return GS Milly TaxFund Mapping Output value for
||                CORP, Member and Product values of GS Milly taxFund Value by mapping with the Mapping set Name/code.
||                Passing CORP, Member and Product values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the GS MILLY
|| i_member               ---  Member value of the GS MILLY
|| i_product              ---  Product Value as returned from the GsMillyProductValue function
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  28-JUL-16        Leila Stotter                         Initial version
||    2.1 19-FEB-19        Leila van Diggele      0030446_1497732_FAH_Milly_RMM_Product_to_TaxFund_Mapping
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (20) := '000';
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_RMM_TAXFUND_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_RMM_TAXFUND';
  l_err_msg              VARCHAR2(2000);
BEGIN
 IF i_corp = 'SF3' THEN
    BEGIN
       /* v2.1 SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_product;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_product;  --v2.0 */

        SELECT value_constant    --v2.1 start
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code1
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_member;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_member; --v2.0
                --v2.1 end

        RETURN l_output_value;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            BEGIN
                /* v2.1 SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code1
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_member;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_member; --v2.0 */

               SELECT value_constant  --v2.1 start
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_product;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_product;
               --v2.1 end

                RETURN l_output_value;
            EXCEPTION
                WHEN NO_DATA_FOUND  THEN
                      --v2.0 xla_mapping_set_flavors does not exist in EBS
--                    SELECT default_constant
--                    INTO   l_default_output
--                    FROM   xla_mapping_set_flavors
--                    WHERE  mapping_set_code = l_mapping_set_code1;

                    ----v2.0
                    SELECT value_constant
                    INTO   l_default_output
                    FROM   xla_mapping_set_values
                    WHERE  mapping_set_code      = l_mapping_set_code1
                    AND    enabled_flag          = 'Y'
                    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                    AND    input_value_type_code = 'D';
                    ----v2.0

                    l_output_value := l_default_output;
                    RETURN l_output_value;
            END;
    END;
 ELSIF i_corp = 'GSN' THEN
    BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_member;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_member;  --v2.0

        RETURN l_output_value;
    EXCEPTION
        WHEN NO_DATA_FOUND  THEN
                --v2.0 xla_mapping_set_flavors does not exist in EBS
--             SELECT default_constant
--             INTO   l_default_output
--             FROM   xla_mapping_set_flavors
--             WHERE  mapping_set_code = l_mapping_set_code1;

            ----v2.0
            SELECT value_constant
            INTO   l_default_output
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            AND    input_value_type_code = 'D';
            ----v2.0

            l_output_value := l_default_output;
            RETURN l_output_value;
    END;
 ELSE
    l_output_value := i_corp;
    RETURN l_output_value;  
 END IF;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
   -- fnd_file.put_line (fnd_file.log, 'Error in GsMillyTaxFundValue (Fn)-GsMillyTaxFundValue:'|| l_err_msg);  OC_Comment
    RAISE;
END GsMillyTaxFundValue;

FUNCTION EbMillyAccountValue ( i_corp      IN   VARCHAR2,
                               i_account   IN   VARCHAR2,
                               i_ccentre   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: EbMillyAccountValue
||   Description: This function EbMillyAccountValue is to Return EB Milly Account Mapping Output value for
||                CORP, Account and Cost Centre values of EB Milly by mapping with the Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the EB MILLY
|| i_account              ---  Account value of the EB MILLY
|| i_ccentre              ---  Cost Centre Value of the EB MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_accnt_ccentre        VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_accnt                VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_EB_ACCOUNT_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_EB_ACCOUNT';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_accnt_ccentre :=  (i_account || '.' || i_ccentre);
  l_accnt         :=  (i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_accnt_ccentre; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_accnt;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_accnt; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          l_output_value := l_accnt;
         -- RETURN l_output_value;  OC_Comment
         RAISE;  --Added by OC_Comment
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in EbMillyAccountValue (Fn)-EbMillyAccountValue:' || l_err_msg);   OC_Comment
    RAISE;
END EbMillyAccountValue;

FUNCTION EbRelatedPartyValue ( i_corp      IN   VARCHAR2,
                               i_account   IN   VARCHAR2,
                               i_ccentre   IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: EbRelatedPartyValue
||   Description: This function EbRelatedPartyValue is to Return EB Related Party Mapping Output value for
||                 CORP, Account and Cost Centre values of EB Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the EB MILLY
|| i_account              ---  Account value of the EB MILLY
|| i_ccentre              ---  Cost Centre Value of the EB MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt           VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (50) := '0000';
  l_accnt                VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_EB_RELATED_PARTY_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_EB_RELATED_PARTY';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_accnt    :=  (i_corp || '.' || i_account);
  l_accnt         :=  (i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_accnt;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_accnt; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
            --v2.0 xla_mapping_set_flavors does not exist in EBS
--          SELECT default_constant
--          INTO   l_default_output
--          FROM   xla_mapping_set_flavors
--          WHERE  mapping_set_code = l_mapping_set_code1;

            ----v2.0
            SELECT value_constant
            INTO   l_default_output
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            AND    input_value_type_code = 'D';
            ----v2.0

           l_output_value := l_default_output;
           RETURN l_output_value;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in EbRelatedPartyValue (Fn)-EbRelatedPartyValue:'|| l_err_msg);   OC_Comment
    RAISE;
END EbRelatedPartyValue;

FUNCTION EbProductValue ( i_corp      IN   VARCHAR2,
                          i_account   IN   VARCHAR2,
                          i_ccentre   IN   VARCHAR2,
                          i_fund      IN   VARCHAR2,
                          i_scheme    IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: EbProductValue
||   Description: This function EbProductValue is to Return EB Product Value Mapping Output value for
||                 CORP, Account and Cost Centre values of EB Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the EB MILLY
|| i_account              ---  Account value of the EB MILLY
|| i_ccentre              ---  Cost Centre Value of the EB MILLY
|| i_fund                 ---  Fund Value of the EB MILLY
|| i_scheme               ---  Scheme Value of the EB MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
||   1.1  27-Feb-13        Swathi                             Changed as per V3.0 FDD
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_ccentre              VARCHAR2 (50);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (50) := '00000';
  l_accnt                VARCHAR2 (50);
  l_fund                 VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_EB_PRODUCT_DEV2';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_EB_PRODUCT_DEV1';
  l_mapping_set_code2    VARCHAR2 (50) := 'FAH_MIL_EB_PRODUCT';
  l_err_msg              VARCHAR2(2000);
  l_mapping_set_code3    VARCHAR2 (50) := 'FAH_MIL_EB_PRODUCT_DEV3'; -- Added as per V3.0 FDD
BEGIN
  l_ccentre :=  (i_ccentre);
  l_accnt   :=  (i_account);
  l_fund    :=  (i_fund);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_accnt; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- Start of changes as per V3.0 FDD
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code3
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_scheme||'.'||i_fund;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_scheme||'.'||i_fund;  --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND  THEN
      -- End of changes as per V3.0 FDD
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_fund;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_fund; --v2.0

            RETURN l_output_value;
          EXCEPTION
            WHEN NO_DATA_FOUND  THEN
              BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code2
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = l_ccentre;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = l_ccentre; --v2.0

                RETURN l_output_value;
              EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    --v2.0 xla_mapping_set_flavors does not exist in EBS
--                  SELECT default_constant
--                  INTO   l_default_output
--                  FROM   xla_mapping_set_flavors
--                  WHERE  mapping_set_code = l_mapping_set_code2;

                    ----v2.0
                    SELECT value_constant
                    INTO   l_default_output
                    FROM   xla_mapping_set_values
                    WHERE  mapping_set_code      = l_mapping_set_code2
                    AND    enabled_flag          = 'Y'
                    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                    AND    input_value_type_code = 'D';
                    ----v2.0

                    l_output_value := l_default_output;
                    RETURN l_output_value;
              END;
          END;
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in EbProductValue (Fn)-EbProductValue:'|| l_err_msg);   OC_Comment
    RAISE;
END EbProductValue;

FUNCTION EbTaxFundValue ( i_corp      IN   VARCHAR2,
                          i_ccentre   IN   VARCHAR2,
                          i_member    IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: EbTaxFundValue
||   Description: This function EbTaxFundValue is to Return EB TaxFund Value Mapping Output value for
||                 CORP, Cost Centre and Member values of EB Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Cost Centre and Member values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the EB MILLY
|| i_ccentre              ---  Cost Centre Value of the EB MILLY
|| i_member               ---  Member Value of the EB MILLY
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  27-Jun-16       Leila Stotter                       Initial version
| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_default_output       VARCHAR2 (50) := '000';
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_EB_CC_TAXFUND';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_EB_TAXFUND';
  l_err_msg              VARCHAR2(2000);

BEGIN

 IF i_corp = 'SAV' THEN
    BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_ccentre; --v2.0

        RETURN l_output_value;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code1
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_member;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_member; --v2.0

                RETURN l_output_value;
            EXCEPTION
                WHEN NO_DATA_FOUND  THEN
                    --v2.0 xla_mapping_set_flavors does not exist in EBS
--                    SELECT default_constant
--                    INTO   l_default_output
--                    FROM   xla_mapping_set_flavors
--                    WHERE  mapping_set_code = l_mapping_set_code1;

                    ----v2.0
                    SELECT value_constant
                    INTO   l_default_output
                    FROM   xla_mapping_set_values
                    WHERE  mapping_set_code      = l_mapping_set_code1
                    AND    enabled_flag          = 'Y'
                    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                    AND    input_value_type_code = 'D';
                    ----v2.0

                    l_output_value := l_default_output;
                    RETURN l_output_value;
            END;
    END;
 ELSIF i_corp in ('NAV', 'NAO') THEN
    BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_member;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_member; --v2.0

        RETURN l_output_value;
    EXCEPTION
        WHEN NO_DATA_FOUND  THEN
             --v2.0 xla_mapping_set_flavors does not exist in EBS
--             SELECT default_constant
--             INTO   l_default_output
--             FROM   xla_mapping_set_flavors
--             WHERE  mapping_set_code = l_mapping_set_code1;

            ----v2.0
            SELECT value_constant
            INTO   l_default_output
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            AND    input_value_type_code = 'D';
            ----v2.0

            l_output_value := l_default_output;
            RETURN l_output_value;
    END;
 ELSE
    l_output_value := i_corp;
    RETURN l_output_value;
 END IF;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in EbProductValue (Fn)-EbProductValue:'|| l_err_msg);  OC_Comment
    RAISE;
END EbTaxFundValue;

FUNCTION IlsaMillyCostCentreValue (
      i_corp                 IN   VARCHAR2,
      i_account              IN   VARCHAR2,
      i_ccentre              IN   VARCHAR2,
      i_fund                 IN   VARCHAR2,
      i_transaction_number   IN   NUMBER,
      i_line_number          IN   NUMBER )
RETURN VARCHAR2
AS
/*
||   Function: IlsaMillyCostCentreValue
||   Description: This Function IlsaMillyCostCentreValue is to Return ILSA Milly Centre Mapping Output value for
||                 CORP, Account and Cost Centre values of ILSA Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Account,Fund and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILSA Millie
|| i_account              ---  Account value of the ILSA Millie
|| i_ccentre              ---  Cost Centre Value of the ILSA Millie
|| i_fund                 ---  Fund value of the ILSA Millie
|| i_transaction_number   ---  transaction number
|| i_line_number          ---  line number
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt           VARCHAR2 (100);
  l_ccentre              VARCHAR2 (50);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_corp_ccentre         VARCHAR2 (100);
  l_corp                 VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_ILSA_CC_PREMAP1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_ILSA_CC_PREMAP2';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_ccentre :=  (i_corp || '.' || i_ccentre);
  l_corp_accnt   :=  (i_corp || '.' || i_account);
  l_ccentre      :=  (i_ccentre);
  l_corp         :=  (i_corp);

  BEGIN

    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_ccentre; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          l_output_value := l_ccentre;
          
      END;
  END;

  UPDATE xxfah_passthrough_lines
  SET    new_centre          = l_output_value,
         corp_new_centre     = (l_corp || '.' || l_output_value),
         new_fund_new_centre = i_fund||'.'||l_output_value,
         corp_accnt_centre   = l_corp_accnt||'.'||l_output_value
  WHERE  transaction_number  = i_transaction_number
  AND    line_number         = i_line_number;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsaMillyCostCentreValue (Fn)-IlsaMillyCostCentreValue:' || l_err_msg);    OC_Comment
    RAISE;
END IlsaMillyCostCentreValue;

FUNCTION IlsaMillyFundValue (
      i_corp                 IN   VARCHAR2,
      i_account              IN   VARCHAR2,
      i_new_ccentre          IN   VARCHAR2,
      i_fund                 IN   VARCHAR2,
      i_transaction_number   IN   VARCHAR2,
      i_line_number          IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: IlsaMillyFundValue
||   Description: This function IlsaMillyFundValue is to Return ILSA Milly Fund Mapping Output value for
||                CORP, Account and Cost Centre values of ILSA Milly by mapping with the Mapping set Name/code.
||                Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILSA Milly
|| i_account              ---  Account value of the ILSA Milly
|| i_new_ccentre          ---  New Cost Centre Value of the ILSA Milly
|| i_fund                 ---  Fund Value of the ILSA Milly
|| i_transaction_number   ---  transaction number
|| i_line_number          ---  line number
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_new_ccentre   VARCHAR2 (100);
  l_corp_accnt               VARCHAR2 (100);
  l_corp_fund                VARCHAR2 (100);
  l_output_value             xla_mapping_set_values.value_constant%TYPE;
  l_corp_new_ccentre         VARCHAR2 (100);
  l_corp_fund_accnt          VARCHAR2 (150);
  l_fund                     VARCHAR2 (50);
  l_mapping_set_code0        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP0';
  l_mapping_set_code         VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP1';
  l_mapping_set_code1        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP2';
  l_mapping_set_code2        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP3';
  l_mapping_set_code3        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP4';
  l_mapping_set_code4        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP5';
  l_mapping_set_code5        VARCHAR2 (50) := 'FAH_MIL_ILSA_FUND_PREMAP6';
  l_err_msg                  VARCHAR2(2000);
BEGIN
  l_corp_accnt_new_ccentre :=  (i_corp || '.' || i_account || '.' || i_new_ccentre);
  l_corp_accnt             :=  (i_corp || '.' || i_account);
  l_corp_new_ccentre       :=  (i_corp || '.' || i_new_ccentre);
  l_corp_fund              :=  (i_corp || '.' || i_fund);
  l_corp_fund_accnt        :=  (i_corp || '.' || i_fund||'.'||i_account);
  l_fund                   :=  (i_fund);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code0
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_fund_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_fund_accnt; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt_new_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt_new_ccentre; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code1
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_corp_accnt;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_corp_accnt; --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code2
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = l_corp_new_ccentre;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = l_corp_new_ccentre; --v2.0

              EXCEPTION
                WHEN NO_DATA_FOUND THEN
                  BEGIN
                    SELECT value_constant
                    INTO   l_output_value
                    FROM   xla_mapping_set_values
                    WHERE  mapping_set_code      = l_mapping_set_code3
                    AND    enabled_flag          = 'Y'
                    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                    --v2.0 AND    input_value_constant1 = l_corp_fund;
                    AND    input_value_type_code = 'I' --v2.0
                    AND    input_value_constant = l_corp_fund; --v2.0

                  EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                      l_output_value := l_fund;
                  END;
              END;
          END;
      END;
  END;

  IF (l_output_value = '000') THEN
    BEGIN
      SELECT value_constant
      INTO   l_output_value
      FROM   xla_mapping_set_values
      WHERE  mapping_set_code      = l_mapping_set_code4
      AND    enabled_flag          = 'Y'
      AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
      --v2.0 AND    input_value_constant1 = l_corp_accnt_new_ccentre;
      AND    input_value_type_code = 'I' --v2.0
      AND    input_value_constant = l_corp_accnt_new_ccentre; --v2.0

    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        BEGIN
          SELECT value_constant
          INTO   l_output_value
          FROM   xla_mapping_set_values
          WHERE  mapping_set_code      = l_mapping_set_code5
          AND    enabled_flag          = 'Y'
          AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
          --v2.0 AND    input_value_constant1 = l_corp_new_ccentre;
          AND    input_value_type_code = 'I' --v2.0
          AND    input_value_constant = l_corp_new_ccentre; --v2.0

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            NULL;
        END;
    END;
  END IF;

  UPDATE xxfah_passthrough_lines
  SET    new_fund            = l_output_value,
         new_fund_new_centre = l_output_value||'.'||i_new_ccentre
  WHERE  transaction_number  = i_transaction_number
  AND    line_number         = i_line_number;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsaMillyFundValue (Fn)-IlsaMillyFundValue:'|| l_err_msg);  OC_Comment
    RAISE;
END IlsaMillyFundValue;

FUNCTION IlsaMillyAccountValue (
      i_corp          IN   VARCHAR2,
      i_account       IN   VARCHAR2,
      i_new_ccentre   IN   VARCHAR2 )
RETURN VARCHAR2
AS
/*
||   Function: IlsaMillyAccountValue
||   Description: This function IlsaMillyAccountValue is to Return ILSA Milly Account Mapping Output value for
||                 CORP, Account and Cost Centre values of ILSA Millie by mapping with the Mapping set Name/code.
||                 Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILSA Millie
|| i_account              ---  Account value of the ILSA Millie
|| i_new_ccentre          ---  New Cost Centre Value of the ILSA Millie
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt               VARCHAR2 (100);
  l_accnt                    VARCHAR2 (50);
  l_output_value             xla_mapping_set_values.value_constant%TYPE;
  l_corp_accnt_ccentre       VARCHAR2 (100);
  l_mapping_set_code         VARCHAR2 (50) := 'FAH_MIL_IL_ACCOUNT';
  l_mapping_set_code1        VARCHAR2 (50) := 'FAH_MIL_IL_ACCOUNT_DEV1';
  l_err_msg                  VARCHAR2(2000);

BEGIN
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_account || '.' || i_new_ccentre);
  l_accnt              :=  (i_account);
  l_corp_accnt         :=  (i_corp || '.' || i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt; --v2.0

    RETURN l_output_value;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

        RETURN l_output_value;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          l_output_value := l_accnt;
          --RETURN l_output_value;  OC_Comment
          RAISE;   -- Added by OC_Comment
      END;
  END;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsaMillyAccountValue (Fn)-ILSA MILLIE ACCOUNT:'|| l_err_msg);   OC_Comment
    RAISE;
END IlsaMillyAccountValue;

FUNCTION IlsamillyProductValue (
      i_corp          IN   VARCHAR2,
      i_account       IN   VARCHAR2,
      i_new_ccentre   IN   VARCHAR2,
      i_new_fund      IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: IlsamillyProductValue
||   Description: This function IlsamillyProductValue is to Return ILSA Milly Product Mapping Output value for
||                 CORP, Account and Cost Centre values of ILSA Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILSA Milly
|| i_account              ---  Account value of the ILSA Milly
|| i_new_ccentre          ---  New Cost Centre Value of the ILSA Milly
|| i_new_fund             ---  New fund Value of the ILSA Milly
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_new_fund               VARCHAR2 (50);
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_new_fund_new_ccentre   VARCHAR2 (100);
  l_corp_new_fund          VARCHAR2 (100);
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_MIL_ILSA_PRODUCT_DEV1';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_MIL_ILSA_PRODUCT';
  l_mapping_set_code2      VARCHAR2 (50) := 'FAH_MIL_ILSA_PRODUCT_DEV2';
  l_err_msg                VARCHAR2(2000);
BEGIN
  l_corp_new_fund        :=  (i_corp || '.' || i_new_fund);
  l_new_fund             :=  (i_new_fund);
  l_new_fund_new_ccentre :=  (i_new_fund || '.' || i_new_ccentre);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_new_fund_new_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_new_fund_new_ccentre; --v2.0

    BEGIN
      SELECT value_constant
      INTO   l_output_value
      FROM   xla_mapping_set_values
      WHERE  mapping_set_code      = l_mapping_set_code2
      AND    enabled_flag          = 'Y'
      AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
      --v2.0 AND    input_value_constant1 = l_corp_new_fund;
      AND    input_value_type_code = 'I' --v2.0
      AND    input_value_constant = l_corp_new_fund; --v2.0

    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_new_fund;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_new_fund; --v2.0

        BEGIN
          SELECT value_constant
          INTO   l_output_value
          FROM   xla_mapping_set_values
          WHERE  mapping_set_code      = l_mapping_set_code2
          AND    enabled_flag          = 'Y'
          AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
          --v2.0 AND    input_value_constant1 = l_corp_new_fund;
          AND    input_value_type_code = 'I' --v2.0
          AND    input_value_constant = l_corp_new_fund; --v2.0

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            NULL;
        END;

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
         -- l_output_value := l_new_fund; Comment by OC
         RAISE;  --Added by OC
      END;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsamillyProductValue (Fn)-ILSA MILLIE PRODUCT:'|| l_err_msg);   OC_Comment
    RAISE;
END IlsamillyProductValue;

FUNCTION IlsaTaxFundValue (
      i_corp          IN   VARCHAR2,
      i_account       IN   VARCHAR2,
      i_new_ccentre   IN   VARCHAR2,
      i_new_fund      IN   VARCHAR2 )
RETURN VARCHAR2
AS
/*
||   Function: IlsaTaxFundValue
||   Description: This function IlsaTaxFundValue is to Return ILSA Milly Tax Fund Mapping Output value for
||                 CORP, Account and Cost Centre values of ILSA Milly by mapping with the Mapping set Name/code.
||                 Passing CORP, Account and Cost Centre values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILSA Milly
|| i_account              ---  Account value of the ILSA Milly
|| i_new_ccentre          ---  New Cost Centre Value of the ILSA Milly
|| i_new_fund             ---  New fund Value of the ILSA Milly
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_new_fund               VARCHAR2 (50);
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_corp_new_fund          VARCHAR2 (100);
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_MIL_ILSA_TAXFUND_DEV1';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_MIL_ILSA_TAXFUND';
  l_err_msg                VARCHAR2(2000);
BEGIN
  l_corp_new_fund        :=  (i_corp || '.' || i_new_fund);
  l_new_fund             :=  (i_new_fund);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_new_fund;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_new_fund; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_new_fund;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_new_fund; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          
        l_output_value := l_new_fund;  
          
      END;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsaTaxFundValue (Fn)-ILSA MILLY TAX FUND:'|| l_err_msg);  OC_Comment
    RAISE;
END IlsaTaxFundValue;

FUNCTION IlnaMillyAccountValue (
      i_corp                 IN   VARCHAR2,
      i_account              IN   VARCHAR2,
      i_ccentre              IN   VARCHAR2,
      i_fund                 IN   VARCHAR2,
      i_transaction_number   IN   VARCHAR2,
      i_line_number          IN   VARCHAR2 )
RETURN VARCHAR2
AS
/*
||   Function: IlnaMillyAccountValue
||   Description: This function IlnaMillyAccountValue is to Return ILNA Account Mapping Output value for
||                 CORP, Account, Cost Centre and Fund values of ILNA by mapping with the Pre Mapping set Name/code.
||                 Passing CORP, Account, Cost Centre and Fund values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILNA
|| i_account              ---  Account value of the ILNA
|| i_ccentre              ---  Cost Centre Value of the ILNA
|| i_fund                 ---  Fund value of the ILNA
|| i_transaction_number   ---  Transaction Number
|| i_line_number          ---  Line Number
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_fund_accnt      VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_accnt                VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_ILNA_MACC_PREMAP1';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_fund_accnt :=  (i_corp || '.' || i_fund || '.' || i_account);
  l_accnt           :=  (i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_fund_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_fund_accnt; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      l_output_value := l_accnt; 
     
  END;

  UPDATE xxfah_passthrough_lines
  SET    new_accnt          = l_output_value,
         corp_new_accnt     = (i_corp||'.'||l_output_value),
         corp_accnt_centre  = i_corp||'.'||l_output_value||'.'||i_ccentre
  WHERE  transaction_number = i_transaction_number
  AND    line_number        = i_line_number;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlsaMillyAccountValue (Fn)-ILSA MILLIE ACCOUNT:' || l_err_msg);  OC_Comment
    RAISE;
END IlnaMillyAccountValue;

FUNCTION IlnaCostCentreValue (
      i_corp                 IN   VARCHAR2,
      i_new_account          IN   VARCHAR2,
      i_ccentre              IN   VARCHAR2,
      i_fund                 IN   VARCHAR2,
      i_transaction_number   IN   NUMBER,
      i_line_number          IN   NUMBER )
RETURN VARCHAR2
AS
/*
||   Function: IlnaCostCentreValue
||   Description: This function IlnaCostCentreValue is to Return ILNA Cost Centre Mapping Output value for
||                CORP, Account, Cost Centre and Fund values of ILNA by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account, Cost Centre and Fund values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILNA
|| i_new_account          ---  New Account value of the ILNA
|| i_ccentre              ---  Cost Centre Value of the ILNA
|| i_fund                 ---  Fund Value of the ILNA
|| i_transaction_number   ---  Transaction Number
|| i_line_number          ---  Line Number
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt_ccentre   VARCHAR2 (100);
  l_corp_accnt           VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_corp_ccentre         VARCHAR2 (100);
  l_ccentre              VARCHAR2 (50);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_ILNA_CC_PREMAP1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_ILNA_CC_PREMAP2';
  l_mapping_set_code2    VARCHAR2 (50) := 'FAH_MIL_ILNA_CC_PREMAP3';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_new_account || '.' || i_ccentre);
  l_corp_accnt         :=  (i_corp || '.' || i_new_account);
  l_corp_ccentre       :=  (i_corp || '.' || i_ccentre);
  l_ccentre            := (i_ccentre);
  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_corp_ccentre;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_corp_ccentre; --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
             l_output_value := l_ccentre;  
             
          END;
      END;
  END;

  UPDATE xxfah_passthrough_lines
  SET    new_centre          = l_output_value,
         corp_new_centre     = (i_corp||'.'||l_output_value),
         corp_accnt_centre   = i_corp||'.'||i_new_account||'.'||l_output_value,
         new_fund_new_centre = i_fund||'.'||l_output_value
  WHERE  transaction_number  = i_transaction_number
  AND    line_number         = i_line_number;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlnaCostCentreValue (Fn)-ILNA COST CENTRE:'|| l_err_msg);   OC_Comment
    RAISE;
END IlnaCostCentreValue;

FUNCTION IlnaMillyFundValue (
      i_corp               IN   VARCHAR2,
      i_new_account        IN   VARCHAR2,
      i_new_ccentre        IN   VARCHAR2,
      i_fund               IN   VARCHAR2,
      i_transaction_number IN   NUMBER,
      i_line_number        IN   NUMBER )
RETURN VARCHAR2
AS
/*
||   Function: IlnaMillyFundValue
||   Description: This function IlnaMillyFundValue is to Return ILNA Fund Mapping Output value for
||                CORP, Account, Cost Centre and Fund values of ILNA by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account, Cost Centre and Fund values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILNA
|| i_new_account          ---  New Account value of the ILNA
|| i_new_ccentre          ---  New Cost Centre Value of the ILNA
|| i_fund                 ---  Fund value of the ILNA
|| i_transaction_number   ---  Transaction Number
|| i_line_number          ---  Line Number
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  28-Feb-11       Srinivas Maram  - Accenture          Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_fund_accnt_ccentre   VARCHAR2 (150);
  l_corp_accnt_ccentre        VARCHAR2 (100);
  l_corp_accnt                VARCHAR2 (100);
  l_output_value              xla_mapping_set_values.value_constant%TYPE;
  l_corp_fund                 VARCHAR2 (100);
  l_corp_ccentre              VARCHAR2 (100);
  l_fund                      VARCHAR2 (50);
  l_mapping_set_code          VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP1';
  l_mapping_set_code1         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP2';
  l_mapping_set_code2         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP3';
  l_mapping_set_code3         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP4';
  l_mapping_set_code4         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP5';
  l_mapping_set_code5         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP6';
  l_mapping_set_code6         VARCHAR2 (50) := 'FAH_MIL_ILNA_FUND_PREMAP7';
  l_err_msg                   VARCHAR2(2000);
BEGIN
  l_corp_fund_accnt_ccentre :=  (i_corp || '.' || i_fund || '.' || i_new_account || '.' || i_new_ccentre);
  l_corp_accnt_ccentre      :=  (i_corp || '.' || i_new_account || '.' || i_new_ccentre);
  l_corp_accnt              :=  (i_corp || '.' || i_new_account);
  l_corp_ccentre            :=  (i_corp || '.' || i_new_ccentre);
  l_corp_fund               :=  (i_corp || '.' || i_fund);
  l_fund                    := (i_fund);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_fund_accnt_ccentre;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_fund_accnt_ccentre; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_corp_accnt;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_corp_accnt; --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code3
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = l_corp_ccentre;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = l_corp_ccentre; --v2.0

              EXCEPTION
                WHEN NO_DATA_FOUND THEN
                  BEGIN
                    SELECT value_constant
                    INTO   l_output_value
                    FROM   xla_mapping_set_values
                    WHERE  mapping_set_code      = l_mapping_set_code4
                    AND    enabled_flag          = 'Y'
                    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                    --v2.0 AND    input_value_constant1 = l_corp_fund;
                    AND    input_value_type_code = 'I' --v2.0
                    AND    input_value_constant = l_corp_fund; --v2.0

                  EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                      l_output_value := l_fund;
                  END;
              END;
          END;
      END;
  END;

  IF (l_output_value = '000') THEN
    BEGIN
      SELECT value_constant
      INTO   l_output_value
      FROM   xla_mapping_set_values
      WHERE  mapping_set_code      = l_mapping_set_code5
      AND    enabled_flag          = 'Y'
      AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
      --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
      AND    input_value_type_code = 'I' --v2.0
      AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        BEGIN
          SELECT value_constant
          INTO   l_output_value
          FROM   xla_mapping_set_values
          WHERE  mapping_set_code      = l_mapping_set_code6
          AND    enabled_flag          = 'Y'
          AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
          --v2.0 AND    input_value_constant1 = l_corp_ccentre;
          AND    input_value_type_code = 'I' --v2.0
          AND    input_value_constant = l_corp_ccentre; --v2.0

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            NULL;
        END;
    END;
  END IF;

  UPDATE xxfah_passthrough_lines
  SET    new_fund            = l_output_value,
         new_fund_new_centre = l_output_value||'.'||i_new_ccentre
  WHERE  transaction_number  = i_transaction_number
  AND    line_number         = i_line_number;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlnaMillyFundValue (Fn)-ILNA MILLIY FUND:'||l_err_msg);   OC_Comment
    RAISE;
END IlnaMillyFundValue;

FUNCTION IlnaAccountValue (
      i_corp           IN   VARCHAR2,
      i_new_account    IN   VARCHAR2,
      i_new_ccentre    IN   VARCHAR2 )
RETURN VARCHAR2
AS
/*
||   Function: IlnaAccountValue
||   Description: This function IlnaAccountValue is to Return ILNA Account Mapping Output value for
||                CORP, Account, Cost Centre and Fund values of ILNA by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account, Cost Centre and Fund values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILNA
|| i_new_account          ---  New Account value of the ILNA
|| i_new_ccentre          ---  New Cost Centre Value of the ILNA
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_accnt                VARCHAR2 (100);
  l_corp_accnt_ccentre        VARCHAR2 (100);
  l_output_value              xla_mapping_set_values.value_constant%TYPE;
  l_accnt                     VARCHAR2 (50);
  l_mapping_set_code          VARCHAR2 (50) := 'FAH_MIL_IL_ACCOUNT';
  l_mapping_set_code1         VARCHAR2 (50) := 'FAH_MIL_IL_ACCOUNT_DEV1';
  l_err_msg                   VARCHAR2(2000);
BEGIN
  l_corp_accnt         :=  (i_corp || '.' || i_new_account);
  l_corp_accnt_ccentre :=  (i_corp || '.' || i_new_account || '.' || i_new_ccentre);
  l_accnt              :=  (i_new_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_accnt; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = l_corp_accnt_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = l_corp_accnt_ccentre; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
         l_output_value := l_accnt; 
         
      END;
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlnaAccountValue (Fn)-ILNA MILLY ACCOUNT:'||l_err_msg);  OC_Comment
    RAISE;
END IlnaAccountValue;

FUNCTION IlnaProductValue (
      i_corp        IN   VARCHAR2,
      i_account     IN   VARCHAR2,
      i_new_ccentre IN   VARCHAR2,
      i_new_fund    IN   VARCHAR2)
RETURN VARCHAR2
AS
/*
||   Function: IlnaProductValue
||   Description: This function IlnaProductValue is to Return ILNA Product Mapping Output value for
||                CORP, Account, Cost Centre and Fund values of ILNA by mapping with the Pre Mapping set Name/code.
||                Passing CORP, Account, Cost Centre and Fund values as Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                 ---  CORP value of the ILNA
|| i_account              ---  Account value of the ILNA
|| i_new_ccentre          ---  Cost Centre Value of the ILNA
|| i_new_fund             ---  New Fund value of the ILNA
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_fund                 VARCHAR2 (50);
  l_corp_fund            VARCHAR2 (100);
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_ILNA_PRODUCT_DEV1';
  l_mapping_set_code1    VARCHAR2 (50) := 'FAH_MIL_ILNA_PRODUCT_DEV2';
  l_mapping_set_code2    VARCHAR2 (50) := 'FAH_MIL_ILNA_PRODUCT';
  l_err_msg              VARCHAR2(2000);
BEGIN
  l_fund               :=  (i_new_fund);
  l_corp_fund          :=  (i_corp || '.' || i_new_fund);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_fund;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_fund; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_new_fund||'.'||i_new_ccentre;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_new_fund||'.'||i_new_ccentre; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = l_fund;
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = l_fund; --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              l_output_value := l_fund;
             
          END;
      END;
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in IlnaProductValue (Fn)-ILNA MILLY PRODUCT:'||l_err_msg);   OC_Comment
    RAISE;
END IlnaProductValue;

--Start of changes for Oracle layout 27-Feb-2013
/*FUNCTION OraAdminProductValue (
      i_segment1       IN   VARCHAR2,
      i_segment5       IN   VARCHAR2 )
RETURN VARCHAR2
AS

||   Function: OraAdminProductValue
||   Description: This function OraAdminProductValueis to Return Oracle Product Mapping Output value
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_segment1              ---  Balancing Entity value of  ORA
|| i_segment5              ---  Product value of   ORA
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.

  -- Local Variable Declarations
  l_segment15              VARCHAR2 (100);
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_segment5               VARCHAR2 (50);
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_ORA_ADMIN_PRODUCT_DEV1';
  l_err_msg                VARCHAR2(2000);
BEGIN
  l_segment15 :=  (i_segment1||'.'||i_segment5);
  l_segment5  :=  (i_segment5);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    input_value_constant1 = l_segment15;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      l_output_value := l_segment5;
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    fnd_file.put_line (fnd_file.log,'Error in OraAdminProductValue (Fn)-ORA ADMIN PRODUCT VALUE:'||l_err_msg);
    RAISE;
END OraAdminProductValue;

FUNCTION OraAdminTaxValue (
      i_segment1  IN   VARCHAR2,
      i_segment4  IN   VARCHAR2,
      i_segment9  IN   VARCHAR2)
RETURN VARCHAR2
AS

||   Function: OraAdminTaxValue
||   Description: This function OraAdminTaxValue is to Return Oracle Admin Tax Mapping Output value.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_segment1             ---  segment1 value of ORA
|| i_segment4             ---  segment4 value of ORA
|| i_segment9             ---  segment9 value of ORA
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0  07-Oct-11        Kalaiselvan                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.

  -- Local Variable Declarations
  l_segment149             VARCHAR2 (100);
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_segment9               VARCHAR2 (50);
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_ORA_ADMIN_TAXFUND_DEV1';
  l_err_msg                VARCHAR2(2000);
BEGIN
  l_segment149 :=   (i_segment1||'.'||i_segment4||'.'||i_segment9);
  l_segment9   :=   (i_segment9);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    input_value_constant1 = l_segment149;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      l_output_value := l_segment9;
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    fnd_file.put_line (fnd_file.log,'Error in OraAdminTaxValue (Fn)-ORA TAX VALUE:'||l_err_msg);
    RAISE;
END OraAdminTaxValue;
*/

FUNCTION MillyAccountValue ( i_corp          IN   VARCHAR2,
                             i_account       IN   VARCHAR2)

RETURN VARCHAR2
AS
/*
||   Function:  MillyAccountValue
||   Description: This function  is to Return Milly Account Mapping Output value for
||                business units AGD, BDC, GCS and GDS
||                Passing CORP and Account Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_corp                     ---  CORP value
|| i_account                  ---  Account value
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0 01-Apr-2014        Karin Roux                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_corp_new_accnt       VARCHAR2 (100);
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MIL_ACCOUNT';
  l_err_msg              VARCHAR2(2000);

BEGIN
  l_corp_new_accnt :=  (i_corp || '.' || i_account);

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = l_corp_new_accnt;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = l_corp_new_accnt; --v2.0

    RETURN l_output_value;

  EXCEPTION
    WHEN no_data_found THEN
       l_output_value := l_corp_new_accnt;
       RETURN l_output_value;
  END;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in MillyAccountValue (Fn)-MillyAccountValue:' || l_err_msg);  OC_Comment
    RAISE;

END MillyAccountValue;

FUNCTION MDAccountValue(i_account       IN   VARCHAR2)

RETURN VARCHAR2
AS
/*
||   Function:  MDAccountValue
||   Description: This function  is to Return MD Account Mapping Output value for
||                Nigeria
||                Passing Account Input Parameters.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_account                  ---  Account value
|| -----------------------------------------------------------------------------
||   Ver  Date              Author                             Modification
|| -----------------------------------------------------------------------------
||   1.0 25-May-2015        Karin Roux                        Initial version
|| -----------------------------------------------------------------------------
||
||   All rights reserved.
*/
  -- Local Variable Declarations
  l_output_value         xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code     VARCHAR2 (50) := 'FAH_MD_ACCOUNT';
  l_err_msg              VARCHAR2(2000);

BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_account;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_account; --v2.0

    RETURN l_output_value;

  EXCEPTION
    WHEN no_data_found THEN
      l_output_value := i_account;  
        
       RETURN l_output_value;
  END;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in MDAccountValue (Fn)-MillyAccountValue:' || i_account);   OC_Comment
    RAISE;

END MDAccountValue;

FUNCTION RecVatBalEntity ( i_currency  IN  VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: RecVatBalEntity
|| Description: This function RecVatBalEntity is to Return new_segment1 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_currency             ---  currency code from passthrough headers
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE := NULL;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_REC_VAT_BALANCING_ENTITY';
  l_err_msg                VARCHAR2(5000);
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_currency;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_currency; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      NULL;
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in RecVatBalEntity for currency code '||i_currency||' - '||l_err_msg);  OC_Comment
    RAISE;
END RecVatBalEntity;

FUNCTION RecVatAccount ( i_dr_cr_ind  IN  VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: RecVatAccount
|| Description: This function RecVatAccount is to Return new_segment3 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_currency             ---  currency code from passthrough headers
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  01-Apr-14       Karin Roux                      Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE := NULL;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_REC_VAT_ACCOUNT';
  l_err_msg                VARCHAR2(5000);

BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_dr_cr_ind;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_dr_cr_ind; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      NULL;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in RecVatAccount for dr_cr_ind '||i_dr_cr_ind ||' - '||l_err_msg);  OC_Comment
    RAISE;
END RecVatAccount;

FUNCTION CcidToBalEntity ( i_key      IN VARCHAR2,
                           i_segment1 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToBalEntity
|| Description: This function CcidToBalEntity is to Return new_segment1 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_BALANCING_ENTITY';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_BALANCING_ENTITY';
   l_status                        BOOLEAN;
   l_segment1                VARCHAR2 (50)  := i_segment1;
   
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
    
   --  l_output_value := i_segment1; Comment by OC
   
    -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => l_segment1,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := i_segment1; 
                
                END IF;
    
  END;

  RETURN l_output_value;
EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
   -- fnd_file.put_line (fnd_file.log,'Error in CcidToBalEntity for key '||i_key||' - '||l_err_msg);   OC_Comment
    RAISE;
END CcidToBalEntity;

FUNCTION CcidToBudCtr ( i_key      IN VARCHAR2,
                        i_layout   IN VARCHAR2,
                        i_segment2 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToBudCtr
|| Description: This function CcidToBudCtr is to Return new_segment2 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_layout          ---  layout type value
|| i_segment2        ---  segment2 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_BUDGET_CENTRE';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_ORA_BUDGET_CENTRE';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_BUDGET_CENTRE';
   l_status                        BOOLEAN;
BEGIN

  BEGIN

    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN

      IF i_layout = 'O-11' THEN
        BEGIN
          SELECT value_constant
          INTO   l_output_value
          FROM   xla_mapping_set_values
          WHERE  mapping_set_code      = l_mapping_set_code1
          AND    enabled_flag          = 'Y'
          AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
          --v2.0 AND    input_value_constant1 = i_segment2;
          AND    input_value_type_code = 'I' --v2.0
          AND    input_value_constant = i_segment2; --v2.0

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
           -- l_output_value := i_segment2;  Comment by OC
            
           -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => i_segment2,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := i_segment2; 
                
                END IF; 
          
        END;

      ELSE
        --l_output_value := i_segment2;  Comment by OC
        
        -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => i_segment2,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := i_segment2; 
                
                END IF; 
      END IF;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in CcidToBudCtr for key '||i_key||' - '||l_err_msg);   OC_Comment
    RAISE;
END CcidToBudCtr;

FUNCTION CcidToAcct ( i_key      IN VARCHAR2,
                      i_layout   IN VARCHAR2,
                      i_segment1 IN VARCHAR2,
                      i_segment3 IN VARCHAR2,
                      i_segment7 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToAcct
|| Description: This function CcidToAcct is to Return new_segment3 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_layout          ---  layout type value
|| i_segment1        ---  segment1 from passthrough lines
|| i_segment3        ---  segment3 from passthrough lines
|| i_segment7        ---  segment7 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_ACCOUNT';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_ORA_INVESTMENT_ACCOUNT';
  l_err_msg                VARCHAR2(5000);
   l_segment_category       VARCHAR2 (50) := 'OM_ACCOUNT';
   l_status                        BOOLEAN;
  
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      IF i_layout IN ('O-11','ON-11') AND i_segment7 <> '0000' THEN
        BEGIN
          SELECT value_constant
          INTO   l_output_value
          FROM   xla_mapping_set_values
          WHERE  mapping_set_code      = l_mapping_set_code1
          AND    enabled_flag          = 'Y'
          AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
          --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment3||'.'||i_segment7;
          AND    input_value_type_code = 'I' --v2.0
          AND    input_value_constant = i_segment1||'.'||i_segment3||'.'||i_segment7; --v2.0

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            l_output_value := NULL;
        END;
      ELSE
        --l_output_value := i_segment3; comment by OC
        -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => i_segment3,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := i_segment3;
                
                END IF; 
      END IF;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in CcidToAcct for key '||i_key||' - '||l_err_msg);  OC_Comment
    RAISE;
END CcidToAcct;

FUNCTION CcidToRp ( i_key      IN VARCHAR2,
                    i_segment1 IN VARCHAR2,
                    i_segment3 IN VARCHAR2,
                    i_segment4 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToRp
|| Description: This function CcidToRp is to Return new_segment4 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_segment1        ---  segment1 from passthrough lines
|| i_segment3        ---  segment3 from passthrough lines
|| i_segment4        ---  segment4 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_RELATED_PARTY';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_ORA_RELATED_PARTY';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_RELATED_PARTY';
   l_status                        BOOLEAN;
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment3||'.'||i_segment4;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_segment1||'.'||i_segment3||'.'||i_segment4; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          --l_output_value := i_segment4;  Comment by OC
           -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => i_segment4,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := i_segment4;
                
                END IF; 
         
          
      END;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in CcidToRp for key '||i_key||' - '||l_err_msg);
    RAISE;
END CcidToRp;


FUNCTION CcidToProduct ( i_key      IN VARCHAR2,
                         i_layout   IN VARCHAR2,
                         i_segment1 IN VARCHAR2,
                         i_segment3 IN VARCHAR2,
                         i_segment5 IN VARCHAR2,
                         i_segment7 IN VARCHAR2,
                         i_segment9 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToProduct
|| Description: This function CcidToProduct is to Return new_segment5 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_layout          ---  layout type value
|| i_segment1        ---  segment1 from passthrough lines
|| i_segment3        ---  segment3 from passthrough lines
|| i_segment5        ---  segment5 from passthrough lines
|| i_segment7        ---  segment7 from passthrough lines
|| i_segment9        ---  segment9 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_PRODUCT';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_ORA_PRODUCT_DEV1';
  l_mapping_set_code2      VARCHAR2 (50) := 'FAH_ORA_PRODUCT_DEV2';
  l_mapping_set_code3      VARCHAR2 (50) := 'FAH_ORA_PRODUCT_DEV3';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_PRODUCT';
   l_status                        BOOLEAN;
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment3||'.'||i_segment5;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_segment1||'.'||i_segment3||'.'||i_segment5; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment5||'.'||DECODE(i_layout,'O-8',i_segment7,i_segment9);
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = i_segment1||'.'||i_segment5||'.'||DECODE(i_layout,'O-8',i_segment7,i_segment9); --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code3
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment5;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_segment1||'.'||i_segment5; --v2.0

              EXCEPTION
                WHEN NO_DATA_FOUND THEN
               --  l_output_value := i_segment5; OC_COMMENT
               
                -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => i_segment5,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
               l_output_value := i_segment5;
                
                END IF; 
                 
              END;
          END;
      END;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in CcidToProduct for key '||i_key||' - '||l_err_msg);  OC_Comment
    RAISE;
END CcidToProduct;

FUNCTION CcidToScheme ( i_key      IN VARCHAR2,
                        i_layout   IN VARCHAR2,
                        i_segment6 IN VARCHAR2,
                        i_segment8 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToScheme
|| Description: This function CcidToScheme is to Return new_segment6 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_layout          ---  layout type value
|| i_segment6        ---  segment6 from passthrough lines
|| i_segment8        ---  segment8 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_SCHEME';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_SCHEME';
   l_status                        BOOLEAN;
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      SELECT DECODE(i_layout,'O-8',i_segment6,i_segment8)
      INTO   l_output_value
      FROM   dual;
      
      -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => l_output_value,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := l_output_value; 
                
                END IF; 
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
   -- fnd_file.put_line (fnd_file.log,'Error in CcidToScheme for key '||i_key||' - '||l_err_msg);   OC_Comment
    RAISE;
END CcidToScheme;

FUNCTION CcidToTaxFund ( i_key      IN VARCHAR2,
                         i_layout   IN VARCHAR2,
                         i_segment1 IN VARCHAR2,
                         i_segment3 IN VARCHAR2,
                         i_segment4 IN VARCHAR2,
                         i_segment5 IN VARCHAR2,
                         i_segment7 IN VARCHAR2,
                         i_segment9 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: CcidToTaxFund
|| Description: This function CcidToTaxFund is to Return new_segment7 value for oracle layouts.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_key             ---  concatenated segments from passthrough lines
|| i_layout          ---  layout type value
|| i_segment1        ---  segment1 from passthrough lines
|| i_segment3        ---  segment3 from passthrough lines
|| i_segment4        ---  segment4 from passthrough lines
|| i_segment5        ---  segment5 from passthrough lines
|| i_segment7        ---  segment7 from passthrough lines
|| i_segment9        ---  segment9 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver  Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  27-Feb-13        Swathi                        Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_mapping_set_code       VARCHAR2 (50) := 'FAH_CCID_TO_TAXFUND';
  l_mapping_set_code1      VARCHAR2 (50) := 'FAH_ORA_TAXFUND_DEV1';
  l_mapping_set_code2      VARCHAR2 (50) := 'FAH_ORA_TAXFUND_DEV2';
  l_mapping_set_code3      VARCHAR2 (50) := 'FAH_ORA_TAXFUND_DEV3';
  l_err_msg                VARCHAR2(5000);
  l_segment_category       VARCHAR2 (50) := 'OM_TAX_FUND';
   l_status                        BOOLEAN;
BEGIN

  BEGIN
    SELECT value_constant
    INTO   l_output_value
    FROM   xla_mapping_set_values
    WHERE  mapping_set_code      = l_mapping_set_code
    AND    enabled_flag          = 'Y'
    AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
    --v2.0 AND    input_value_constant1 = i_key;
    AND    input_value_type_code = 'I' --v2.0
    AND    input_value_constant = i_key; --v2.0

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      BEGIN
        SELECT value_constant
        INTO   l_output_value
        FROM   xla_mapping_set_values
        WHERE  mapping_set_code      = l_mapping_set_code1
        AND    enabled_flag          = 'Y'
        AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
        --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment3||'.'||i_segment5;
        AND    input_value_type_code = 'I' --v2.0
        AND    input_value_constant = i_segment1||'.'||i_segment3||'.'||i_segment5; --v2.0

      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          BEGIN
            SELECT value_constant
            INTO   l_output_value
            FROM   xla_mapping_set_values
            WHERE  mapping_set_code      = l_mapping_set_code2
            AND    enabled_flag          = 'Y'
            AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
            --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment4||'.'||DECODE(i_layout,'O-8',i_segment7,i_segment9);
            AND    input_value_type_code = 'I' --v2.0
            AND    input_value_constant = i_segment1||'.'||i_segment4||'.'||DECODE(i_layout,'O-8',i_segment7,i_segment9); --v2.0

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              BEGIN
                SELECT value_constant
                INTO   l_output_value
                FROM   xla_mapping_set_values
                WHERE  mapping_set_code      = l_mapping_set_code3
                AND    enabled_flag          = 'Y'
                AND    trunc(sysdate)        BETWEEN trunc(nvl(effective_date_from,sysdate)) and trunc(nvl(effective_date_to,sysdate))  --v2.0
                --v2.0 AND    input_value_constant1 = i_segment1||'.'||i_segment5;
                AND    input_value_type_code = 'I' --v2.0
                AND    input_value_constant = i_segment1||'.'||i_segment5; --v2.0

              EXCEPTION
                WHEN NO_DATA_FOUND THEN
                  SELECT DECODE(i_layout,'O-8',i_segment7,i_segment9)
                  INTO   l_output_value
                  FROM   dual;
                  
                  -- Added funnction to check segment value as part of for CR 404
    
    GetSegmentValues(i_segmentvalue => l_output_value,
                 i_segment_category => l_segment_category,
                 o_status      => l_status);

                IF l_status = FALSE THEN
                    
                   RAISE;
					
				Else
				
                l_output_value := l_output_value; 
                
                END IF; 
              END;
          END;
      END;
  END;

  RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in CcidToTaxFund for key '||i_key||' - '||l_err_msg);   OC_Comment
    RAISE;
END CcidToTaxFund;

FUNCTION ValidateAccount (i_segment3 IN VARCHAR2)
RETURN VARCHAR2 AS
/*
|| Function: ValidateAccount
|| Description: This function ValidateAccount is to validate that the Account value
||     is not a control account.
|| -----------------------------------------------------------------------------
|| Parameters
|| -----------------------------------------------------------------------------
|| i_segment3        ---  segment3 from passthrough lines
|| -----------------------------------------------------------------------------
|| Ver   Date             Author                        Modification
|| -----------------------------------------------------------------------------
|| 1.0  01-Apr-14        Karin Roux                    Initial version
|| -----------------------------------------------------------------------------
*/
  -- Local Variable Declarations
  l_output_value           xla_mapping_set_values.value_constant%TYPE;
  l_err_msg                VARCHAR2(5000);
  l_control_flag           VARCHAR2(50);
  CNTRL_ACC_EXCEPTION     EXCEPTION;  --Added by OC_Comment
BEGIN

  l_output_value := i_segment3;

  BEGIN
      --v2.0 SELECT  substr(f.COMPILED_VALUE_ATTRIBUTES, 9,1)
      /*SELECT  substr(f.COMPILED_VALUE_ATTRIBUTES, 7,1) --v2.0
      INTO    l_control_flag
      FROM    fnd_flex_values f
      WHERE   f.flex_value_set_id =
               (SELECT flex_value_set_id
                FROM   fnd_flex_value_sets s
                WHERE  s.FLEX_VALUE_SET_NAME = 'OM_ACCOUNT')
      AND     f.flex_value = i_segment3;

	  SELECT  mapping_set_code 
	  INTO    l_control_flag
       FROM   xla_mapping_set_values 
	   where mapping_set_code=i_segment3;

      IF l_control_flag is not null THEN
         l_output_value := substr('ControlAcc'||i_segment3, 1, 25);
      END IF;*/

      SELECT  lookup_code 
	  INTO    l_control_flag
       FROM   FND_LOOKUP_VALUES 
	   where lookup_code=i_segment3
       AND LOOKUP_TYPE='XXFAH_OM_CNTRL_ACCOUNT'
        AND enabled_flag = 'Y'
       AND TRUNC(SYSDATE) BETWEEN TRUNC(NVL(start_date_active,SYSDATE))
                       AND TRUNC(NVL(end_date_active,SYSDATE));

       IF l_control_flag is not null THEN
        --l_output_value := i_segment3; --Comment by OC_Comment
        RAISE CNTRL_ACC_EXCEPTION; 
      END IF;



       EXCEPTION
    WHEN NO_DATA_FOUND THEN

    RETURN l_output_value;

    when CNTRL_ACC_EXCEPTION then

    raise;

     /* IF l_control_flag is not null THEN
        --l_output_value := i_segment3; --Comment by OC_Comment
        RAISE CNTRL_ACC_EXCEPTION; 
      END IF;*/

  --EXCEPTION
    -- return original value if the account value is invalid, this will be validated with the
    -- standard Create Accounting validation.
  --  WHEN CNTRL_ACC_EXCEPTION THEN
    --  raise;
  END;

 --RETURN l_output_value;

EXCEPTION
  WHEN OTHERS THEN
    l_err_msg := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE ||'. SQLERRM: '||SQLERRM;
    --fnd_file.put_line (fnd_file.log,'Error in ValidateAccount for segment3 '||i_segment3||' - '||l_err_msg);  OC_Comment
    RAISE;
END ValidateAccount;

END XXFAH_GET_MAPPING_OUTPUT_PKG;