create or replace PACKAGE "XXAGIS_UTILITY_PKG" AS
--------------------------------------------------------------------------------
-- Owner                : ORACLE Technical Team
-- Project              : OML
-- RICE ID              :
-- Program Type         : Package Specification
--
-- Modification History:
--    ========= ================== ================== =================================
--    Version   Date               Author             Comments
--    ========= ================== ================== ==================================
--    1.0       7-Aug-20          Benjamin T             Initial Version
--    2.0       6-Aug-20          Piyasa/Vidya           3-26648617891 / 2706282391
--    3.0       19-Sep-22         Tahzeeb                3-30676503231
--    4.0       21-Oct-22         Tahzeeb                BSR1827102 | SR 3-30826230451     
--    5.0       27-Feb-23         Tahzeeb                CEN-2985 | SR 3-32323763401
--    6.0       24-OCT-24         Mahesh                 CEN-8063 | Credit Note Enhancements
--	  7.0       10-JUL-25         Animesh                CEN-8274 | AGIS stuck file issue
--------------------------------------------------------------------------------

    gc_status VARCHAR2(50) := 'New';
    gc_template VARCHAR2(50);
    gc_user VARCHAR2(150);
	--Change for CEN-8274 Start
	gc_oic_not_reachable VARCHAR2(30) := 'OIC Not Reachable';
	--Change for CEN-8274 End
    PROCEDURE agis_call_bip_report (
        p_report_name VARCHAR2,
        p_user_name   VARCHAR2
    );--,p_report_type VARCHAR2,p_username VARCHAR2);
    PROCEDURE base64_decode (
        p_clob CLOB,
        l_clob OUT CLOB
    );

    PROCEDURE agis_insert_data (
        p_report_name VARCHAR2,
        p_user_name   VARCHAR2
    );

    PROCEDURE agis_lookup_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_value_set_values_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_gl_calendar_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_gl_dates_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_sync_user_role (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_system_options_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_period_statuses_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_gl_ledgers_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_gl_periods_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_gl_period_statuses_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_interco_organizations_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_customer_account_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_customer_party_sites_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_customer_account_sites_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_customer_site_use_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_customer_account_site_profile_insert_update (
        p_user_name VARCHAR2
    );
--PROCEDURE AGIS_CUSTOMER_TAX_INSERT_UPDATE(P_USER_NAME varchar2); -- 3-26648617891 AGIS CR
    PROCEDURE agis_execute_bip_report_procs (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_related_party_hierarchy_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_error_messages_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE writetolog (
        module_p     IN VARCHAR2,
        sub_module_p IN VARCHAR2,
        log_level_p  IN VARCHAR2,
        comments_p   IN VARCHAR2,
        job_name_p   IN VARCHAR2
    );

    FUNCTION get_agis_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB;
    -- BSR1827102_SR 3-30826230451 new procedure generate_agis_csv_data                                               
    PROCEDURE generate_agis_csv_data (
        file_id_p NUMBER
    );

    FUNCTION get_ra_interface_lines_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB;

    FUNCTION get_ra_interface_distributions_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB;

    FUNCTION get_agis_logs_zip (
        file_id_p NUMBER
    ) RETURN BLOB;

    FUNCTION get_file_interface_status (
        file_id_p NUMBER
    ) RETURN VARCHAR2;

    /*PROCEDURE trigger_oic_process (
        file_id_p NUMBER
    );*/

	--Change for CEN-8274 Start
	PROCEDURE trigger_oic_process (
        file_id_p NUMBER,
		file_source_p VARCHAR2 DEFAULT NULL,
		count_p NUMBER DEFAULT 0
    );

	PROCEDURE retrigger_oic_process;
	--Change for CEN-8274 End

    PROCEDURE agis_customer_supply_map_insert_update (
        p_user_name VARCHAR2
    );

    PROCEDURE agis_poz_supplier_sites_insert_update (
        p_user_name VARCHAR2
    );
 --CEN_8063_Start   
    PROCEDURE agis_call_bip_report_adhoc (
        p_report_name  VARCHAR2,
        p_user_name    VARCHAR2,
        p_from_date    VARCHAR2,
        p_to_date      VARCHAR2,
        p_file_id_from NUMBER,
        p_file_id_to   NUMBER
    );

    PROCEDURE agis_original_invoice_update (
        p_user_name VARCHAR2
    );
  --CEN_8063_End  
END xxagis_utility_pkg;
