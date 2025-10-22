create or replace PACKAGE BODY "XXAGIS_UTILITY_PKG" AS
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
	--    2.0       22-SEP-21         Vidya Sagar            3-26961848861/2706282391 : Enable logging in TRIGGER_OIC_PROCESS
	--    2.1       09-DEC-21         Vidya Sagar            3-27580827611 : AGIS_GL_DATES_INSERT_UPDATE 
	--    3.1       19-SEP-22         Tahzeeb                3-30676503231 : Remove TREE_NODE_ID from Related Party Hierarchy Sync procedure
    --    4.0       21-Oct-22         Tahzeeb                BSR1827102 | SR 3-30826230451 : GENERATE_AGIS_CSV_DATA, Separated CLOB generation and CLOB return to OIC          
    --    5.0       27-Feb-23         Tahzeeb                CEN-2985 | SR 3-32323763401 : Delete logic for duplicates in AGIS_RELATED_PARTY_HIERARCHY_INSERT_UPDATE
	--    6.0       24-May-23          Sakshi                CEN-8040 | SR 3-36490370391 : OFC Dev1 | AGIS Duplicate orphans after P2T
	--    7.0       15-OCT-24         Mahesh                 CEN-8063 Credit Note Enhancements | Updating Original Invoice Number
    --    7.1      2025-02-24         Mahesh                 CEN-12837 - INC0389333 - AGIS Invoice Number Sync not syncing correctly 
    --    7.2      2025-03-06         MAHESH                 CEN – 12951 – SR 3-39945034771 – R2R| PRB0042226| Unable to reverse AGIS Duplicate Line History Transactions
	--    8.0      2025-07-10         Animesh				 CEN-8274 | SR 3-36992258811 : AGIS transactions stuck log file error message
	--														  1. 'RETRIGGER_OIC_PROCESS' was created to pick files which needs reprocessing.
	--														  2. 'TRIGGER_OIC_PROCESS' was updated to reprocess the files that are stuck.
	--														  3. 'GET_AGIS_LOGS_ZIP' was updated to create OIC_ERROR_LOGS.zip file
	--														  4. 'GET_FILE_INTERFACE_STATUS' updated to display file_interface_status as ERROR on --														    ADF page when the file is not transferred successfully.
	--------------------------------------------------------------------------------

	/***************************************************************************
	*
	*  PROCEDURE: WRITETOLOG
	*
	*  Description:  This procedure is for writing messages into xxagis_logs table
	*
	**************************************************************************/

    PROCEDURE writetolog (
        module_p     IN VARCHAR2,
        sub_module_p IN VARCHAR2,
        log_level_p  IN VARCHAR2,
        comments_p   IN VARCHAR2,
        job_name_p   IN VARCHAR2
    ) IS
        PRAGMA autonomous_transaction;
    BEGIN
        INSERT INTO xxagis_logs (
            log_id,
            module,
            sub_module,
            comments,
            creation_date,
            log_level,
            job_name
        ) VALUES (
            xxagis_logs_seq.NEXTVAL,
            module_p,
            sub_module_p,
            comments_p,
            sysdate,
            log_level_p,
            job_name_p
        );

        COMMIT;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'writetolog', p_tracker => 'writetolog',
            p_custom_err_info => 'EXCEPTION1 : writetolog');
    END writetolog;

	/***************************************************************************
	*
	*  FUNCTION: BASE64_DECODE
	*
	*  Description:  Used to decode XXAGIs_soap_connection_details data
	*
	**************************************************************************/

    PROCEDURE base64_decode (
        p_clob CLOB,
        l_clob OUT CLOB
    ) IS

        l_length INTEGER := dbms_lob.getlength(p_clob);
        l_offset INTEGER := 1;
        l_amt    BINARY_INTEGER := 800;
        l_buffer VARCHAR2(3200);
    BEGIN
        l_clob := empty_clob();
        WHILE l_offset <= l_length LOOP
            l_clob := l_clob
                      || utl_raw.cast_to_varchar2(utl_encode.base64_decode(utl_raw.cast_to_raw(dbms_lob.substr(p_clob, l_amt, l_offset))));

            l_offset := l_offset + l_amt;
        END LOOP;

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'base64_decode', p_tracker => 'base64_decode',
            p_custom_err_info => 'EXCEPTION1 : base64_decode');
    END base64_decode;

	/***************************************************************************
	*
	*  FUNCTION: AGIS_CALL_BIP_REPORT
	*
	*  Description:  Procedure used to fetch XXAGIS_soap_connection_details and sync BIP Reports into  xxagis_from_base64 table
	*
	**************************************************************************/

    PROCEDURE agis_call_bip_report (
        p_report_name VARCHAR2,
        p_user_name   VARCHAR2
    ) AS

        CURSOR xx_get_conn_details_cur (
            p_username VARCHAR2
        ) IS
        SELECT
            *
        FROM
            xxagis_soap_connection_details
        WHERE
            source = 'ERP';

        xx_get_conn_details_rec xx_get_conn_details_cur%rowtype;
        l_envelope              CLOB;
        l_xml                   XMLTYPE;
        l_result                VARCHAR2(32767);
        l_base64                CLOB;
        l_blob                  BLOB;
        l_clob                  CLOB;
        l_http_request          utl_http.req;
        l_http_response         utl_http.resp;
        l_string_request        VARCHAR2(32000);
        buff                    VARCHAR2(32000);
        l_url                   VARCHAR2(1000);
        l_username              VARCHAR2(100);
        l_password              VARCHAR2(100);
        l_wallet_path           VARCHAR2(1000);
        l_wallet_password       VARCHAR2(100);
        l_process               VARCHAR2(1000);
        l_path                  VARCHAR2(100);
        l_tablename             VARCHAR2(100);
        l_reportname            VARCHAR2(100);
        l_parameter_name        VARCHAR2(100) := 'P_START_DATE';
        l_parameter_username    VARCHAR2(100) := 'p_user_name';
        l_parameter_value       VARCHAR2(100);
        l_proxy                 VARCHAR2(100);
    BEGIN
        gc_template := p_report_name;
        gc_user := 'PBSAdmin';--p_username;
        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker => 'BEGIN',
        p_custom_err_info => 'gc_template' || p_report_name);

        DELETE FROM xxagis_logs
        WHERE
                job_name = p_report_name
            AND creation_date <= sysdate;

        BEGIN
			------log----------
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', 'Procedure used to fetch XXAGIS_soap_connection_details and sync BIP Reports into xxagis_from_base64 table ',
            p_report_name);
			 ------------------------
            OPEN xx_get_conn_details_cur(gc_user); --p_username
			-- Fetch connection details to variables
            FETCH xx_get_conn_details_cur INTO xx_get_conn_details_rec;
            l_url := xx_get_conn_details_rec.url;
            l_username := xx_get_conn_details_rec.username;
            l_password := xx_get_conn_details_rec.password;
            l_wallet_path := xx_get_conn_details_rec.wallet_path;
            l_wallet_password := xx_get_conn_details_rec.wallet_password;
            l_proxy := xx_get_conn_details_rec.proxy_details;
				  -- close cursor
            CLOSE xx_get_conn_details_cur;
            dbms_output.put_line('l_url: ' || l_url);
            dbms_output.put_line('l_username: ' || l_username);
            dbms_output.put_line('l_wallet_path: ' || l_wallet_path);
            dbms_output.put_line('l_proxy: ' || l_proxy);
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', l_url
                                                                                  || ' '
                                                                                  || l_username
                                                                                  || ' '
                                                                                  || l_wallet_path
                                                                                  || ' '
                                                                                  || l_proxy, p_report_name);

        END;

        BEGIN
            SELECT
                decode(p_report_name, 'AGIS_LOOKUP_VALUES', 'XXAGIS_LOOKUP_VALUES', 'AGIS_VALUE_SET_VALUES', 'XXAGIS_VALUE_SET_VALUES',
                       'AGIS_GL_CALENDAR', 'GL_TRANSACTION_CALENDAR', 'AGIS_GL_DATES', 'GL_TRANSACTION_DATES', 'USER_ROLE_REPORT',
                       'XXAGIS_USER_ROLE_MAP', 'AGIS_SYSTEM_OPTIONS', 'XXAGIS_FUN_SYSTEM_OPTIONS', 'AGIS_PERIOD_STATUSES', 'XXAGIS_FUN_PERIOD_STATUSES',
                       'AGIS_GL_PERIOD_STATUSES', 'GL_PERIOD_STATUSES', 'AGIS_GL_PERIODS', 'GL_PERIODS', 'AGIS_GL_LEDGER',
                       'GL_LEDGERS', 'AGIS_INTERCO_ORGANIZATIONS', 'XXAGIS_FUN_INTERCO_ORGANIZATIONS', 'AGIS_CUSTOMER_ACCOUNT', 'XXAGIS_CUSTOMER_ACCOUNT',
                       'AGIS_CUSTOMER_PARTY_SITES', 'XXAGIS_CUSTOMER_PARTY_SITES', 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL', 'XXAGIS_CUSTOMER_ACCOUNT_SITES_ALL',
                       'AGIS_CUSTOMER_SITES_USE',
                       'XXAGIS_CUSTOMER_SITE_USE_ALL', 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', 'XXAGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', 'AGIS_RELATED_PARTY_HIERACHY',
                       'XXAGIS_RELATED_PARTY_HIERARCHY',
                       'AGIS_ERROR_MESSAGES', 'XXAGIS_FND_NEW_MESSAGES', 'AGIS_CUSTOMER_SUPPLY_MAP', 'XXAGIS_FUN_IC_CUST_SUPP_MAP', 'AGIS_POZ_SUPPLIER_SITES',
                       'XXAGIS_POZ_SUPPLIER_SITES_V', 'dual')                           tablename,
                decode(p_report_name, 'AGIS_LOOKUP_VALUES', '/AGIS/Old Mutual - AGIS - Lookup Extract Report.xdo', 'AGIS_VALUE_SET_VALUES',
                '/AGIS/Old Mutual - AGIS - Value Set Extract Report.xdo',
                       'AGIS_GL_CALENDAR', '/Integration/AHCS/GL Transaction Calendar/Old Mutual - INT - GL Transaction Calendar Extract.xdo',
                       'AGIS_GL_DATES', '/Integration/AHCS/GL Transaction Date/Old Mutual - INT - GL Transaction Date Extract.xdo', 'USER_ROLE_REPORT',
                       '/AGIS/Old Mutual - AGIS - User Data Extract Report.xdo', 'AGIS_SYSTEM_OPTIONS', '/AGIS/Old Mutual - AGIS - System Options Extract Report.xdo',
                       'AGIS_PERIOD_STATUSES', '/AGIS/Old Mutual - AGIS - Period Statuses Extract Report.xdo',
                       'AGIS_GL_PERIOD_STATUSES', '/Integration/AHCS/GL Period Statuses/Old Mutual - INT - GL Period Statuses Extract.xdo',
                       'AGIS_GL_PERIODS', '/Integration/AHCS/GL Periods/Old Mutual - INT - GL Periods Extract.xdo', 'AGIS_GL_LEDGER',
                       '/Integration/AHCS/GL Ledgers Extract/Old Mutual - INT - GL Ledgers Extract.xdo', 'AGIS_INTERCO_ORGANIZATIONS',
                       '/AGIS/Old Mutual - AGIS - Interco Organizations Report.xdo', 'AGIS_CUSTOMER_ACCOUNT', '/AGIS/Old Mutual - AGIS - Customer Account Report.xdo',
                       'AGIS_CUSTOMER_PARTY_SITES', '/AGIS/Old Mutual - AGIS - Customer Party Sites Report.xdo', 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL',
                       '/AGIS/Old Mutual - AGIS - Customer Account Sites All Report.xdo', 'AGIS_CUSTOMER_SITES_USE',
                       '/AGIS/Old Mutual - AGIS - Customer Account Site Use All Report.xdo', 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', '/AGIS/Old Mutual - AGIS - Customer Account Site Profile Report.xdo',
                       'AGIS_RELATED_PARTY_HIERACHY', '/AGIS/Old Mutual - AGIS - Related Party Hierarchy Report.xdo',
                       'AGIS_ERROR_MESSAGES', '/AGIS/Old Mutual - AGIS - Error Messages Report.xdo', 'AGIS_CUSTOMER_SUPPLY_MAP', '/AGIS/Old Mutual - AGIS - Interco Customer Supplier Map Report.xdo',
                       'AGIS_POZ_SUPPLIER_SITES',
                       '/AGIS/Old Mutual - AGIS - POZ Supplier Sites Report.xdo', NULL) reportname
            INTO
                l_tablename,
                l_reportname
            FROM
                dual;
		---------------------------------------------------------------			

	----------------------------------------------------------------------------

        END;

        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker => 'l_tablename',
        p_custom_err_info => 'gc_template' || p_report_name);

        IF
            l_tablename IS NOT NULL
            AND l_tablename NOT IN ( 'dual' )
            AND p_report_name NOT LIKE 'USER_ROLE_REPORT'
        THEN
            EXECUTE IMMEDIATE 'SELECT TO_CHAR(MAX(last_update_date)-1,''MM-DD-YYYY HH24:MI:SS'') FROM ' || l_tablename
            INTO l_parameter_value;
        END IF;

        IF l_parameter_value IS NULL THEN
            l_parameter_value := to_char(sysdate - 1000, 'MM-DD-YYYY HH24:MI:SS');
        END IF;

        dbms_output.put_line('l_parameter_value: ' || l_parameter_value);
        IF p_report_name LIKE 'USER_ROLE_REPORT' THEN
            l_envelope := '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">
				   <soapenv:Header/>
				   <soapenv:Body>
					  <pub:runReport>
						 <pub:reportRequest>
							<pub:attributeFormat>xml</pub:attributeFormat>
							<pub:attributeLocale>en-US</pub:attributeLocale>
							<pub:parameterNameValues>
							  <pub:item>
								<pub:name>'
                          || l_parameter_username
                          || '</pub:name>
								<pub:values>
								   <pub:item>'
                          || p_user_name
                          || '</pub:item>
								</pub:values>
							  </pub:item>
							</pub:parameterNameValues>
							<pub:reportAbsolutePath>/Custom'
                          || l_reportname
                          || '</pub:reportAbsolutePath>
							 <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>
						 </pub:reportRequest>
						 <pub:userID>'
                          || l_username
                          || '</pub:userID>
						 <pub:password>'
                          || l_password
                          || '</pub:password>
					  </pub:runReport>
				   </soapenv:Body>
				</soapenv:Envelope>';
        ELSE
            l_envelope := '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">
				   <soapenv:Header/>
				   <soapenv:Body>

					  <pub:runReport>
						 <pub:reportRequest>
							<pub:attributeFormat>xml</pub:attributeFormat>
							<pub:attributeLocale>en-US</pub:attributeLocale>
							<pub:parameterNameValues>
							  <pub:item>
								<pub:name>'
                          || l_parameter_name
                          || '</pub:name>
								<pub:values>
								   <pub:item>'
                          || l_parameter_value
                          || '</pub:item>
								</pub:values>
							  </pub:item>
							</pub:parameterNameValues>
							<pub:reportAbsolutePath>/Custom'
                          || l_reportname
                          || '</pub:reportAbsolutePath>
							  <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>
						 </pub:reportRequest>
						 <pub:userID>'
                          || l_username
                          || '</pub:userID>
						 <pub:password>'
                          || l_password
                          || '</pub:password>
					  </pub:runReport>
				   </soapenv:Body>
				</soapenv:Envelope>';
        END IF;

        IF ( l_proxy IS NOT NULL ) THEN
            utl_http.set_proxy(l_proxy);
        END IF;
        BEGIN
				--dbms_output.put_line('l_envelope: ' || l_envelope);
            BEGIN
                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', substr(l_envelope, 1, 1000), p_report_name || ' Payload');

                l_xml := apex_web_service.make_request(p_url => l_url || '/xmlpserver/services/PublicReportService', p_envelope => l_envelope,
                p_wallet_path => l_wallet_path, p_wallet_pwd => l_wallet_password);

            EXCEPTION
                WHEN OTHERS THEN
                    writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', sqlerrm, 'Error at apex_web_service.make_request');
            END;

            BEGIN
                l_base64 := apex_web_service.parse_xml_clob(p_xml => l_xml, p_xpath => '//reportBytes/text()', p_ns => 'xmlns="http://xmlns.oracle.com/oxp/service/PublicReportService"');

                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', substr(l_xml.getstringval(), 1, 1000), p_report_name ||
                ' l_base64');

            EXCEPTION
                WHEN OTHERS THEN
                    writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'Error at apex_web_service.parse_xml_clob', sqlerrm);
					/* 3-27580827611 Exception Section */
                    oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker =>
                    'agis_call_bip_report', p_custom_err_info => 'Error at apex_web_service.parse_xml_clob');

            END;

	--            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'l_base64 '||substr(l_base64,1000), p_report_name);

            base64_decode(l_base64, l_clob);
            dbms_output.put_line('l_clob received ');
            IF dbms_lob.getlength(l_clob) > 0 THEN
                BEGIN
                    DELETE FROM xxagis_from_base64
                    WHERE
                            template_name = p_report_name
                        AND user_name = p_user_name;

                    INSERT INTO xxagis_from_base64 (
                        loadtime,
                        clobdata,
                        created_by,
                        creation_date,
                        last_update_date,
                        last_updated_by,
                        last_update_login,
                        template_name,
                        user_name
                    ) VALUES (
                        sysdate,
                        l_clob,
                        gc_user,
                        sysdate,
                        sysdate,
                        gc_user,
                        gc_user,
                        p_report_name,
                        p_user_name
                    );

                    agis_insert_data(p_report_name, p_user_name);
                    COMMIT;
                END;
            ELSE
                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', 'BIP RETURNED NO RECORDS '
                                                                                      || 'PARAM N: '
                                                                                      || l_parameter_value
                                                                                      || ' V:'
                                                                                      || l_parameter_name, p_report_name);
            END IF;

        END;

    EXCEPTION
        WHEN OTHERS THEN
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'Error '
                                                                              || substr(sqlerrm, 1, 1000), 'agis_call_bip_report ');
           /* 3-27580827611 Exception Section */
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker =>
            'agis_call_bip_report', p_custom_err_info => 'Error '
                                                                                                                                    ||
                                                                                                                                    substr(
                                                                                                                                    sqlerrm,
                                                                                                                                    1,
                                                                                                                                    1000));

    END;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_INSERT_DATA
	*
	*  Description:  Procedure used to choose package parameters:
	*
	**************************************************************************/

    PROCEDURE agis_insert_data (
        p_report_name VARCHAR2,
        p_user_name   VARCHAR2
    ) AS
    BEGIN
		-------log----------
        writetolog('xxagis_utility_pkg', 'agis_insert_data', 'STATEMENT', 'Procedure used to choose package parameter: ' || p_report_name,
        p_report_name);
	   ----------------------         

        IF p_report_name = 'AGIS_LOOKUP_VALUES' THEN
				--dbms_output.put_line('insert lookup');
            agis_lookup_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_VALUE_SET_VALUES' THEN
	   --         dbms_output.put_line('insert lookup');
            agis_value_set_values_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_GL_CALENDAR' THEN
		 --       dbms_output.put_line('insert lookup');
            agis_gl_calendar_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_GL_DATES' THEN
		   --     dbms_output.put_line('insert lookup');
            agis_gl_dates_insert_update(p_user_name);
        ELSIF p_report_name = 'USER_ROLE_REPORT' THEN
			 --   dbms_output.put_line('insert lookup');
            agis_sync_user_role(p_user_name);
        ELSIF p_report_name = 'AGIS_SYSTEM_OPTIONS' THEN
			   -- dbms_output.put_line('insert lookup');
            agis_system_options_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_PERIOD_STATUSES' THEN
				--dbms_output.put_line('insert lookup');
            agis_period_statuses_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_GL_PERIOD_STATUSES' THEN
			  --  dbms_output.put_line('insert lookup');
            agis_gl_period_statuses_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_GL_PERIODS' THEN
				--dbms_output.put_line('insert lookup');
            agis_gl_periods_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_GL_LEDGER' THEN
				--dbms_output.put_line('insert lookup');
            agis_gl_ledgers_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_INTERCO_ORGANIZATIONS' THEN
				--dbms_output.put_line('insert lookup');
            agis_interco_organizations_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_ACCOUNT' THEN
				--dbms_output.put_line('insert lookup');
            agis_customer_account_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_PARTY_SITES' THEN
				--dbms_output.put_line('insert lookup');
            agis_customer_party_sites_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL' THEN
				--dbms_output.put_line('insert lookup');
            agis_customer_account_sites_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_SITES_USE' THEN
				--dbms_output.put_line('insert lookup');
            agis_customer_site_use_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE' THEN
				--dbms_output.put_line('insert lookup');
            agis_customer_account_site_profile_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_RELATED_PARTY_HIERACHY' THEN
				--dbms_output.put_line('insert lookup');
            agis_related_party_hierarchy_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_ERROR_MESSAGES' THEN
				--dbms_output.put_line('insert lookup');
            agis_error_messages_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_CUSTOMER_SUPPLY_MAP' THEN
            agis_customer_supply_map_insert_update(p_user_name);
        ELSIF p_report_name = 'AGIS_POZ_SUPPLIER_SITES' THEN
            agis_poz_supplier_sites_insert_update(p_user_name);
		--CEN_8063_Start
		ELSIF p_report_name = 'XXAGIS_FUN_INTERFACE_HEADERS' THEN   
         agis_original_invoice_update(p_user_name);
        --CEN_8063_End
        END IF;

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_insert_data', p_tracker => 'agis_insert_data',
            p_custom_err_info => 'EXCEPTION1 : agis_insert_data');
    END;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_LOOKUP_INSERT_UPDATE
	*
	*  Description:  Syncs Agis Lookup Values BIP Report into XXAGIS_LOOKUP_VALUES table
	*
	**************************************************************************/

    PROCEDURE agis_lookup_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            lookup_type               xxagis_lookup_values.lookup_type%TYPE,
            lookup_code               xxagis_lookup_values.lookup_code%TYPE,
            meaning                   xxagis_lookup_values.meaning%TYPE,
            description               xxagis_lookup_values.description%TYPE,
            enabled_flag              xxagis_lookup_values.enabled_flag%TYPE,
            start_date_active         xxagis_lookup_values.start_date_active%TYPE,
            end_date_active           xxagis_lookup_values.end_date_active%TYPE,
            change_since_last_refresh xxagis_lookup_values.change_since_last_refresh%TYPE,
            created_by                xxagis_lookup_values.created_by%TYPE,
            creation_date             xxagis_lookup_values.creation_date%TYPE,
            last_updated_by           xxagis_lookup_values.last_updated_by%TYPE,
            last_update_date          xxagis_lookup_values.last_update_date%TYPE,
            last_update_login         xxagis_lookup_values.last_update_login%TYPE,
            tag                       xxagis_lookup_values.tag%TYPE,
            row_id                    xxagis_lookup_values.row_id%TYPE,
            language                  xxagis_lookup_values.language%TYPE,
            source_lang               xxagis_lookup_values.source_lang%TYPE,
            view_application_id       xxagis_lookup_values.view_application_id%TYPE,
            territory_code            xxagis_lookup_values.territory_code%TYPE,
            attribute_category        xxagis_lookup_values.attribute_category%TYPE,
            attribute1                xxagis_lookup_values.attribute1%TYPE,
            attribute2                xxagis_lookup_values.attribute2%TYPE,
            attribute3                xxagis_lookup_values.attribute3%TYPE,
            attribute4                xxagis_lookup_values.attribute4%TYPE,
            attribute5                xxagis_lookup_values.attribute5%TYPE,
            attribute6                xxagis_lookup_values.attribute6%TYPE,
            attribute7                xxagis_lookup_values.attribute7%TYPE,
            attribute8                xxagis_lookup_values.attribute8%TYPE,
            attribute9                xxagis_lookup_values.attribute9%TYPE,
            attribute10               xxagis_lookup_values.attribute10%TYPE,
            attribute11               xxagis_lookup_values.attribute11%TYPE,
            attribute12               xxagis_lookup_values.attribute12%TYPE,
            attribute13               xxagis_lookup_values.attribute13%TYPE,
            attribute14               xxagis_lookup_values.attribute14%TYPE,
            attribute15               xxagis_lookup_values.attribute15%TYPE,
            set_id                    xxagis_lookup_values.set_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
	-------------------------------------
        writetolog('xxagis_utility_pkg', 'agis_lookup_insert_update', 'STATEMENT', 'Procedure running for report name: AGIS_LOOKUP_VALUES',
        'AGIS_LOOKUP_VALUES');
	----------------------------------------------- 
	--update
        OPEN lcu_read_xml_data FOR ( ' SELECT
					lookup_type,
					lookup_code,
					meaning,
					description,
					enabled_flag,
					to_char(to_date(substr(start_date_active, 1, 10), ''YYYY-MM-DD''), ''DD-MON-YYYY''),
					to_char(to_date(substr(end_date_active, 1, 10), ''YYYY-MM-DD''), ''DD-MON-YYYY''),
					change_since_last_refresh,
					x.created_by,
					to_char(to_date(substr(x.creation_date, 1, 10), ''YYYY-MM-DD''), ''DD-MON-YYYY''),
					x.last_updated_by,
					to_char(to_date(substr(x.last_update_dateB, 1, 10), ''YYYY-MM-DD''), ''DD-MON-YYYY''),
					x.last_update_login,
					tag,
					row_id,
					x.language,
					source_lang,
					view_application_id,
					territory_code,
					attribute_category,
					attribute1,
					attribute2,
					attribute3,
					attribute4,
					attribute5,
					attribute6,
					attribute7,
					attribute8,
					attribute9,
					attribute10,
					attribute11,
					attribute12,
					attribute13,
					attribute14,
					attribute15,
					set_id
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS lookup_type VARCHAR2(240) PATH ''./LOOKUP_TYPE'', lookup_code
					VARCHAR2(240) PATH ''./LOOKUP_CODE'', meaning VARCHAR2(240) PATH ''./MEANING'', description VARCHAR2(240) PATH ''./DESCRIPTION'',
					enabled_flag VARCHAR2(240) PATH ''./ENABLED_FLAG'', start_date_active VARCHAR2(240) PATH ''./START_DATE_ACTIVE'', end_date_active
					VARCHAR2(240) PATH ''./END_DATE_ACTIVE'', change_since_last_refresh VARCHAR2(24) PATH ''./CHANGE_SINCE_LAST_REFRESH'',
					created_by VARCHAR2(24) PATH ''./CREATED_BY'', creation_date VARCHAR2(240) PATH ''./CREATION_DATE'', last_updated_by VARCHAR2(
					240) PATH ''./LAST_UPDATED_BY'', last_update_dateB VARCHAR2(240) PATH ''./LAST_UPDATE_DATEB'', last_update_login VARCHAR2(
					240) PATH ''./LAST_UPDATE_LOGIN'', tag VARCHAR2(150) PATH ''./TAG'', row_id VARCHAR2(240) PATH ''./ROW_ID'', language VARCHAR2(
					30) PATH ''./LANGUAGE'', source_lang VARCHAR2(30) PATH ''./SOURCE_LANG'', view_application_id NUMBER PATH ''./VIEW_APPLICATION_ID'',
					territory_code NUMBER PATH ''./TERRITORY_CODE'', attribute_category VARCHAR2(30) PATH ''./ATTRIBUTE_CATEGORY'', attribute1
					VARCHAR2(150) PATH ''./ATTRIBUTE1'', attribute2 VARCHAR2(150) PATH ''./ATTRIBUTE2'', attribute3 VARCHAR2(150) PATH ''./ATTRIBUTE3'',
					attribute4 VARCHAR2(150) PATH ''./ATTRIBUTE4'', attribute5 VARCHAR2(150) PATH ''./ATTRIBUTE5'', attribute6 VARCHAR2(150)
					PATH ''./ATTRIBUTE6'', attribute7 VARCHAR2(150) PATH ''./ATTRIBUTE7'', attribute8 VARCHAR2(150) PATH ''./ATTRIBUTE8'', attribute9
					VARCHAR2(150) PATH ''./ATTRIBUTE9'', attribute10 VARCHAR2(150) PATH ''./ATTRIBUTE10'', attribute11 VARCHAR2(150) PATH
					''./ATTRIBUTE11'', attribute12 VARCHAR2(150) PATH ''./ATTRIBUTE12'', attribute13 VARCHAR2(150) PATH ''./ATTRIBUTE13'', attribute14
					VARCHAR2(150) PATH ''./ATTRIBUTE14'', attribute15 VARCHAR2(150) PATH ''./ATTRIBUTE15'', set_id NUMBER PATH ''./SET_ID'' )x
				WHERE t.template_name LIKE ''AGIS_LOOKUP_VALUES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || ''' 
				AND EXISTS (SELECT 1 FROM XXAGIS_LOOKUP_VALUES L WHERE l.lookup_type=x.lookup_type and l.lookup_code=x.lookup_code)' ); --CEN-8040: Updated the logic to use Lookup type and code rather than row_id

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_lookup_values
            SET
                lookup_type = agis_lookup_xml_data_rec.lookup_type,
                lookup_code = agis_lookup_xml_data_rec.lookup_code,
                meaning = agis_lookup_xml_data_rec.meaning,
                description = agis_lookup_xml_data_rec.description,
                enabled_flag = agis_lookup_xml_data_rec.enabled_flag,
                start_date_active = agis_lookup_xml_data_rec.start_date_active,
                end_date_active = agis_lookup_xml_data_rec.end_date_active,
                change_since_last_refresh = agis_lookup_xml_data_rec.change_since_last_refresh,
                created_by = agis_lookup_xml_data_rec.created_by,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                tag = agis_lookup_xml_data_rec.tag,
                row_id = agis_lookup_xml_data_rec.row_id,
                language = agis_lookup_xml_data_rec.language,
                source_lang = agis_lookup_xml_data_rec.source_lang,
                view_application_id = agis_lookup_xml_data_rec.view_application_id,
                territory_code = agis_lookup_xml_data_rec.territory_code,
                attribute_category = agis_lookup_xml_data_rec.attribute_category,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                set_id = agis_lookup_xml_data_rec.set_id
            WHERE
                --CEN-8040 start
				--row_id LIKE agis_lookup_xml_data_rec.row_id
				lookup_type=agis_lookup_xml_data_rec.lookup_type
				and lookup_code=agis_lookup_xml_data_rec.lookup_code
				--CEN-8040 end
				;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;

	-- Insert
        INSERT INTO xxagis_lookup_values (
            lookup_type,
            lookup_code,
            meaning,
            description,
            enabled_flag,
            start_date_active,
            end_date_active,
            change_since_last_refresh,
            created_by,
            creation_date,
            last_updated_by,
            last_update_date,
            last_update_login,
            tag,
            row_id,
            language,
            source_lang,
            view_application_id,
            territory_code,
            attribute_category,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            set_id
        )
            ( SELECT
                lookup_type,
                lookup_code,
                meaning,
                description,
                enabled_flag,
                to_char(to_date(substr(start_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(end_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                change_since_last_refresh,
                x.created_by,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                to_char(to_date(substr(x.last_update_dateb, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_update_login,
                tag,
                row_id,
                x.language,
                source_lang,
                view_application_id,
                territory_code,
                attribute_category,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                attribute6,
                attribute7,
                attribute8,
                attribute9,
                attribute10,
                attribute11,
                attribute12,
                attribute13,
                attribute14,
                attribute15,
                set_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        lookup_type VARCHAR2(240) PATH './LOOKUP_TYPE',
                        lookup_code VARCHAR2(240) PATH './LOOKUP_CODE',
                        meaning VARCHAR2(240) PATH './MEANING',
                        description VARCHAR2(240) PATH './DESCRIPTION',
                        enabled_flag VARCHAR2(240) PATH './ENABLED_FLAG',
                        start_date_active VARCHAR2(240) PATH './START_DATE_ACTIVE',
                        end_date_active VARCHAR2(240) PATH './END_DATE_ACTIVE',
                        change_since_last_refresh VARCHAR2(24) PATH './CHANGE_SINCE_LAST_REFRESH',
                        created_by VARCHAR2(24) PATH './CREATED_BY',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        last_updated_by VARCHAR2(240) PATH './LAST_UPDATED_BY',
                        last_update_dateb VARCHAR2(240) PATH './LAST_UPDATE_DATEB',
                        last_update_login VARCHAR2(240) PATH './LAST_UPDATE_LOGIN',
                        tag VARCHAR2(150) PATH './TAG',
                        row_id VARCHAR2(240) PATH './ROW_ID',
                        language VARCHAR2(30) PATH './LANGUAGE',
                        source_lang VARCHAR2(30) PATH './SOURCE_LANG',
                        view_application_id NUMBER PATH './VIEW_APPLICATION_ID',
                        territory_code NUMBER PATH './TERRITORY_CODE',
                        attribute_category VARCHAR2(30) PATH './ATTRIBUTE_CATEGORY',
                        attribute1 VARCHAR2(150) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(150) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(150) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(150) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(150) PATH './ATTRIBUTE5',
                        attribute6 VARCHAR2(150) PATH './ATTRIBUTE6',
                        attribute7 VARCHAR2(150) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(150) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(150) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(150) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(150) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(150) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(150) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(150) PATH './ATTRIBUTE14',
                        attribute15 VARCHAR2(150) PATH './ATTRIBUTE15',
                        set_id NUMBER PATH './SET_ID'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_LOOKUP_VALUES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_lookup_values l
                    WHERE
                        --Changes below as per testing on 27Feb24 by Tahzeeb
--                      l.row_id LIKE x.row_id 
					    l.lookup_type=x.lookup_type
					    and l.lookup_code=x.lookup_code
					    --CEN-8040 starts
					    --and l.enabled_flag=x.enabled_flag
					    --CEN-8040 ends
																				--Changes end				
                )
            );

    --CEN-8040 starts
	DELETE FROM XXAGIS_LOOKUP_VALUES 
	WHERE ROWID IN 
		(SELECT ROWID 
			FROM
				(SELECT ROWID,
						lookup_type,
						lookup_code,
						ROW_NUMBER() OVER(PARTITION BY lookup_type , lookup_code ORDER BY LAST_UPDATE_DATE DESC) ROWN
					FROM XXAGIS_LOOKUP_VALUES
				)
			WHERE ROWN > 1
		) ;
	COMMIT ;
	--CEN-8040 ends

	EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_lookup_insert_update', p_tracker =>
            'agis_lookup_insert_update', p_custom_err_info => 'EXCEPTION1 : agis_lookup_insert_update');
    END agis_lookup_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_VALUE_SET_VALUES_INSERT_UPDATE
	*
	*  Description:  Syncs Agis Value Set Values BIP Report into XXAGIS_VALUE_SET_VALUES table
	*
	**************************************************************************/

    PROCEDURE agis_value_set_values_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            row_id                     xxagis_value_set_values.row_id%TYPE,
            flex_value_set_id          xxagis_value_set_values.flex_value_set_id%TYPE,
            flex_value_id              xxagis_value_set_values.flex_value_id%TYPE,
            flex_value                 xxagis_value_set_values.flex_value%TYPE,
            enabled_flag               xxagis_value_set_values.enabled_flag%TYPE,
            start_date_active          xxagis_value_set_values.start_date_active%TYPE,
            end_date_active            xxagis_value_set_values.end_date_active%TYPE,
            summary_flag               xxagis_value_set_values.summary_flag%TYPE,
            parent_flex_value_low      xxagis_value_set_values.parent_flex_value_low%TYPE,
            parent_flex_value_high     xxagis_value_set_values.parent_flex_value_high%TYPE,
            structured_hierarchy_level xxagis_value_set_values.structured_hierarchy_level%TYPE,
            hierarchy_level            xxagis_value_set_values.hierarchy_level%TYPE,
            compiled_value_attributes  xxagis_value_set_values.compiled_value_attributes%TYPE,
            value_category             xxagis_value_set_values.value_category%TYPE,
            attribute1                 xxagis_value_set_values.attribute1%TYPE,
            attribute2                 xxagis_value_set_values.attribute2%TYPE,
            attribute3                 xxagis_value_set_values.attribute3%TYPE,
            attribute4                 xxagis_value_set_values.attribute4%TYPE,
            attribute5                 xxagis_value_set_values.attribute5%TYPE,
            attribute6                 xxagis_value_set_values.attribute6%TYPE,
            attribute7                 xxagis_value_set_values.attribute7%TYPE,
            attribute8                 xxagis_value_set_values.attribute8%TYPE,
            attribute9                 xxagis_value_set_values.attribute9%TYPE,
            attribute10                xxagis_value_set_values.attribute10%TYPE,
            attribute11                xxagis_value_set_values.attribute11%TYPE,
            attribute12                xxagis_value_set_values.attribute12%TYPE,
            attribute13                xxagis_value_set_values.attribute13%TYPE,
            attribute14                xxagis_value_set_values.attribute14%TYPE,
            attribute15                xxagis_value_set_values.attribute15%TYPE,
            attribute16                xxagis_value_set_values.attribute16%TYPE,
            attribute17                xxagis_value_set_values.attribute17%TYPE,
            attribute18                xxagis_value_set_values.attribute18%TYPE,
            attribute19                xxagis_value_set_values.attribute19%TYPE,
            attribute20                xxagis_value_set_values.attribute20%TYPE,
            attribute21                xxagis_value_set_values.attribute21%TYPE,
            attribute22                xxagis_value_set_values.attribute22%TYPE,
            attribute23                xxagis_value_set_values.attribute23%TYPE,
            attribute24                xxagis_value_set_values.attribute24%TYPE,
            attribute25                xxagis_value_set_values.attribute25%TYPE,
            attribute26                xxagis_value_set_values.attribute26%TYPE,
            attribute27                xxagis_value_set_values.attribute27%TYPE,
            attribute28                xxagis_value_set_values.attribute28%TYPE,
            attribute29                xxagis_value_set_values.attribute29%TYPE,
            attribute30                xxagis_value_set_values.attribute30%TYPE,
            attribute31                xxagis_value_set_values.attribute31%TYPE,
            attribute32                xxagis_value_set_values.attribute32%TYPE,
            attribute33                xxagis_value_set_values.attribute33%TYPE,
            attribute34                xxagis_value_set_values.attribute34%TYPE,
            attribute35                xxagis_value_set_values.attribute35%TYPE,
            attribute36                xxagis_value_set_values.attribute36%TYPE,
            attribute37                xxagis_value_set_values.attribute37%TYPE,
            attribute38                xxagis_value_set_values.attribute38%TYPE,
            attribute39                xxagis_value_set_values.attribute39%TYPE,
            attribute40                xxagis_value_set_values.attribute40%TYPE,
            attribute41                xxagis_value_set_values.attribute41%TYPE,
            attribute42                xxagis_value_set_values.attribute42%TYPE,
            attribute43                xxagis_value_set_values.attribute43%TYPE,
            attribute44                xxagis_value_set_values.attribute44%TYPE,
            attribute45                xxagis_value_set_values.attribute45%TYPE,
            attribute46                xxagis_value_set_values.attribute46%TYPE,
            attribute47                xxagis_value_set_values.attribute47%TYPE,
            attribute48                xxagis_value_set_values.attribute48%TYPE,
            attribute49                xxagis_value_set_values.attribute49%TYPE,
            attribute50                xxagis_value_set_values.attribute50%TYPE,
            attribute_sort_order       xxagis_value_set_values.attribute_sort_order%TYPE,
            creation_date              xxagis_value_set_values.creation_date%TYPE,
            created_by                 xxagis_value_set_values.created_by%TYPE,
            last_update_date           xxagis_value_set_values.last_update_date%TYPE,
            last_updated_by            xxagis_value_set_values.last_updated_by%TYPE,
            last_update_login          xxagis_value_set_values.last_update_login%TYPE,
            flex_value_meaning         xxagis_value_set_values.flex_value_meaning%TYPE,
            description                xxagis_value_set_values.description%TYPE,
            flex_value_set_name        xxagis_value_set_values.flex_value_set_name%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_value_set_values_insert_update', 'STATEMENT', 'Procedure running for report name: AGIS_VALUE_SET_VALUES',
        'AGIS_VALUE_SET_VALUES');

	--Update
        OPEN lcu_read_xml_data FOR ( ' SELECT
						 x.ROW_ID
						,x.FLEX_VALUE_SET_ID
						,x.FLEX_VALUE_ID
						,x.FLEX_VALUE
						,x.ENABLED_FLAG
						,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE_ACTIVE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
						,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE_ACTIVE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
						,x.SUMMARY_FLAG
						,x.PARENT_FLEX_VALUE_LOW
						,x.PARENT_FLEX_VALUE_HIGH
						,x.STRUCTURED_HIERARCHY_LEVEL
						,x.HIERARCHY_LEVEL
						,x.COMPILED_VALUE_ATTRIBUTES
						,x.VALUE_CATEGORY
						,x.ATTRIBUTE1
						,x.ATTRIBUTE2
						,x.ATTRIBUTE3
						,x.ATTRIBUTE4
						,x.ATTRIBUTE5
						,x.ATTRIBUTE6
						,x.ATTRIBUTE7
						,x.ATTRIBUTE8
						,x.ATTRIBUTE9
						,x.ATTRIBUTE10
						,x.ATTRIBUTE11
						,x.ATTRIBUTE12
						,x.ATTRIBUTE13
						,x.ATTRIBUTE14
						,x.ATTRIBUTE15
						,x.ATTRIBUTE16
						,x.ATTRIBUTE17
						,x.ATTRIBUTE18
						,x.ATTRIBUTE19
						,x.ATTRIBUTE20
						,x.ATTRIBUTE21
						,x.ATTRIBUTE22
						,x.ATTRIBUTE23
						,x.ATTRIBUTE24
						,x.ATTRIBUTE25
						,x.ATTRIBUTE26
						,x.ATTRIBUTE27
						,x.ATTRIBUTE28
						,x.ATTRIBUTE29
						,x.ATTRIBUTE30
						,x.ATTRIBUTE31
						,x.ATTRIBUTE32
						,x.ATTRIBUTE33
						,x.ATTRIBUTE34
						,x.ATTRIBUTE35
						,x.ATTRIBUTE36
						,x.ATTRIBUTE37
						,x.ATTRIBUTE38
						,x.ATTRIBUTE39
						,x.ATTRIBUTE40
						,x.ATTRIBUTE41
						,x.ATTRIBUTE42
						,x.ATTRIBUTE43
						,x.ATTRIBUTE44
						,x.ATTRIBUTE45
						,x.ATTRIBUTE46
						,x.ATTRIBUTE47
						,x.ATTRIBUTE48
						,x.ATTRIBUTE49
						,x.ATTRIBUTE50
						,x.ATTRIBUTE_SORT_ORDER
						,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
						,x.CREATED_BY
						,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
						,x.LAST_UPDATED_BY
						,x.LAST_UPDATE_LOGIN
						,x.FLEX_VALUE_MEANING
						,x.DESCRIPTION
						,x.FLEX_VALUE_SET_NAME
						FROM
							xxagis_from_base64 t,
							XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS ROW_ID VARCHAR2(150) PATH ''./ROW_ID''
									  ,FLEX_VALUE_SET_ID NUMBER PATH ''./FLEX_VALUE_SET_ID'' ,FLEX_VALUE_ID NUMBER PATH ''./FLEX_VALUE_ID'' ,FLEX_VALUE VARCHAR2(150) PATH ''./FLEX_VALUE''
									  ,ENABLED_FLAG VARCHAR2(30) PATH ''./ENABLED_FLAG'',START_DATE_ACTIVE VARCHAR2(240) PATH ''./START_DATE_ACTIVE''
									  ,END_DATE_ACTIVE VARCHAR2(240) PATH ''./END_DATE_ACTIVE'',SUMMARY_FLAG VARCHAR2(30) PATH ''./SUMMARY_FLAG''
									  ,PARENT_FLEX_VALUE_LOW VARCHAR2(150) PATH ''./PARENT_FLEX_VALUE_LOW'',PARENT_FLEX_VALUE_HIGH VARCHAR2(150) PATH ''./PARENT_FLEX_VALUE_HIGH''
									  ,STRUCTURED_HIERARCHY_LEVEL VARCHAR2(240) PATH ''./STRUCTURED_HIERARCHY_LEVEL'',HIERARCHY_LEVEL VARCHAR2(240) PATH ''./HIERARCHY_LEVEL''
									  ,COMPILED_VALUE_ATTRIBUTES VARCHAR2(240) PATH ''./COMPILED_VALUE_ATTRIBUTES'',VALUE_CATEGORY VARCHAR2(60) PATH ''./VALUE_CATEGORY''
									  ,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1'',ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2'',ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''
									  ,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4'',ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''
									  ,ATTRIBUTE6 VARCHAR2(240) PATH ''./ATTRIBUTE6'',ATTRIBUTE7 VARCHAR2(240) PATH ''./ATTRIBUTE7''
									  ,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8'',ATTRIBUTE9 VARCHAR2(240) PATH ''./ATTRIBUTE9''
									  ,ATTRIBUTE10 VARCHAR2(240) PATH ''./ATTRIBUTE10'',ATTRIBUTE11 VARCHAR2(240) PATH ''./ATTRIBUTE11''
									  ,ATTRIBUTE12 VARCHAR2(240) PATH ''./ATTRIBUTE12'',ATTRIBUTE13 VARCHAR2(240) PATH ''./ATTRIBUTE13''
									  ,ATTRIBUTE14 VARCHAR2(240) PATH ''./ATTRIBUTE14'',ATTRIBUTE15 VARCHAR2(240) PATH ''./ATTRIBUTE15''
									  ,ATTRIBUTE16 VARCHAR2(240) PATH ''./ATTRIBUTE16'',ATTRIBUTE17 VARCHAR2(240) PATH ''./ATTRIBUTE17''
									  ,ATTRIBUTE18 VARCHAR2(240) PATH ''./ATTRIBUTE18'',ATTRIBUTE19 VARCHAR2(240) PATH ''./ATTRIBUTE19''
									  ,ATTRIBUTE20 VARCHAR2(240) PATH ''./ATTRIBUTE20'',ATTRIBUTE21 VARCHAR2(240) PATH ''./ATTRIBUTE21''
									  ,ATTRIBUTE22 VARCHAR2(240) PATH ''./ATTRIBUTE22'',ATTRIBUTE23 VARCHAR2(240) PATH ''./ATTRIBUTE23''
									  ,ATTRIBUTE24 VARCHAR2(240) PATH ''./ATTRIBUTE24'',ATTRIBUTE25 VARCHAR2(240) PATH ''./ATTRIBUTE25''
									  ,ATTRIBUTE26 VARCHAR2(240) PATH ''./ATTRIBUTE26'',ATTRIBUTE27 VARCHAR2(240) PATH ''./ATTRIBUTE27''
									  ,ATTRIBUTE28 VARCHAR2(240) PATH ''./ATTRIBUTE28'',ATTRIBUTE29 VARCHAR2(240) PATH ''./ATTRIBUTE29''
									  ,ATTRIBUTE30 VARCHAR2(240) PATH ''./ATTRIBUTE30'',ATTRIBUTE31 VARCHAR2(240) PATH ''./ATTRIBUTE31''
									  ,ATTRIBUTE32 VARCHAR2(240) PATH ''./ATTRIBUTE32'',ATTRIBUTE33 VARCHAR2(240) PATH ''./ATTRIBUTE33''
									  ,ATTRIBUTE34 VARCHAR2(240) PATH ''./ATTRIBUTE34'',ATTRIBUTE35 VARCHAR2(240) PATH ''./ATTRIBUTE35''
									  ,ATTRIBUTE36 VARCHAR2(240) PATH ''./ATTRIBUTE36'',ATTRIBUTE37 VARCHAR2(240) PATH ''./ATTRIBUTE37''
									  ,ATTRIBUTE38 VARCHAR2(240) PATH ''./ATTRIBUTE38'',ATTRIBUTE39 VARCHAR2(240) PATH ''./ATTRIBUTE39''
									  ,ATTRIBUTE40 VARCHAR2(240) PATH ''./ATTRIBUTE40'',ATTRIBUTE41 VARCHAR2(240) PATH ''./ATTRIBUTE41''
									  ,ATTRIBUTE42 VARCHAR2(240) PATH ''./ATTRIBUTE42'',ATTRIBUTE43 VARCHAR2(240) PATH ''./ATTRIBUTE43''
									  ,ATTRIBUTE44 VARCHAR2(240) PATH ''./ATTRIBUTE44'',ATTRIBUTE45 VARCHAR2(240) PATH ''./ATTRIBUTE45''
									  ,ATTRIBUTE46 VARCHAR2(240) PATH ''./ATTRIBUTE46'',ATTRIBUTE47 VARCHAR2(240) PATH ''./ATTRIBUTE47''
									  ,ATTRIBUTE48 VARCHAR2(240) PATH ''./ATTRIBUTE48'',ATTRIBUTE49 VARCHAR2(240) PATH ''./ATTRIBUTE49''
									  ,ATTRIBUTE50 VARCHAR2(240) PATH ''./ATTRIBUTE50'',ATTRIBUTE_SORT_ORDER NUMBER PATH ''./ATTRIBUTE_SORT_ORDER''
									  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE'',CREATED_BY VARCHAR2(240) PATH ''./CREATED_BY''
									  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE'',LAST_UPDATED_BY VARCHAR2(240) PATH ''./LAST_UPDATED_BY''
									  ,LAST_UPDATE_LOGIN VARCHAR2(240) PATH ''./LAST_UPDATE_LOGIN'',FLEX_VALUE_MEANING VARCHAR2(240) PATH ''./FLEX_VALUE_MEANING''
									  ,DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION'',FLEX_VALUE_SET_NAME VARCHAR2(240) PATH ''./FLEX_VALUE_SET_NAME'') x
						   WHERE  t.template_name LIKE ''AGIS_VALUE_SET_VALUES'' 
						   AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
						   AND EXISTS (SELECT 1 FROM XXAGIS_VALUE_SET_VALUES L  WHERE L.FLEX_VALUE_ID = x.FLEX_VALUE_ID)' ); --CEN-8040: Updated the logic to use Lookup type and code rather than row_id

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_value_set_values
            SET
                row_id = agis_lookup_xml_data_rec.row_id,
                flex_value_set_id = agis_lookup_xml_data_rec.flex_value_set_id,
                flex_value_id = agis_lookup_xml_data_rec.flex_value_id,
                flex_value = agis_lookup_xml_data_rec.flex_value,
                enabled_flag = agis_lookup_xml_data_rec.enabled_flag,
                start_date_active = agis_lookup_xml_data_rec.start_date_active,
                end_date_active = agis_lookup_xml_data_rec.end_date_active,
                summary_flag = agis_lookup_xml_data_rec.summary_flag,
                parent_flex_value_low = agis_lookup_xml_data_rec.parent_flex_value_low,
                parent_flex_value_high = agis_lookup_xml_data_rec.parent_flex_value_high,
                structured_hierarchy_level = agis_lookup_xml_data_rec.structured_hierarchy_level,
                hierarchy_level = agis_lookup_xml_data_rec.hierarchy_level,
                compiled_value_attributes = agis_lookup_xml_data_rec.compiled_value_attributes,
                value_category = agis_lookup_xml_data_rec.value_category,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                attribute16 = agis_lookup_xml_data_rec.attribute16,
                attribute17 = agis_lookup_xml_data_rec.attribute17,
                attribute18 = agis_lookup_xml_data_rec.attribute18,
                attribute19 = agis_lookup_xml_data_rec.attribute19,
                attribute20 = agis_lookup_xml_data_rec.attribute20,
                attribute21 = agis_lookup_xml_data_rec.attribute21,
                attribute22 = agis_lookup_xml_data_rec.attribute22,
                attribute23 = agis_lookup_xml_data_rec.attribute23,
                attribute24 = agis_lookup_xml_data_rec.attribute24,
                attribute25 = agis_lookup_xml_data_rec.attribute25,
                attribute26 = agis_lookup_xml_data_rec.attribute26,
                attribute27 = agis_lookup_xml_data_rec.attribute27,
                attribute28 = agis_lookup_xml_data_rec.attribute28,
                attribute29 = agis_lookup_xml_data_rec.attribute29,
                attribute30 = agis_lookup_xml_data_rec.attribute30,
                attribute31 = agis_lookup_xml_data_rec.attribute31,
                attribute32 = agis_lookup_xml_data_rec.attribute32,
                attribute33 = agis_lookup_xml_data_rec.attribute33,
                attribute34 = agis_lookup_xml_data_rec.attribute34,
                attribute35 = agis_lookup_xml_data_rec.attribute35,
                attribute36 = agis_lookup_xml_data_rec.attribute36,
                attribute37 = agis_lookup_xml_data_rec.attribute37,
                attribute38 = agis_lookup_xml_data_rec.attribute38,
                attribute39 = agis_lookup_xml_data_rec.attribute39,
                attribute40 = agis_lookup_xml_data_rec.attribute40,
                attribute41 = agis_lookup_xml_data_rec.attribute41,
                attribute42 = agis_lookup_xml_data_rec.attribute42,
                attribute43 = agis_lookup_xml_data_rec.attribute43,
                attribute44 = agis_lookup_xml_data_rec.attribute44,
                attribute45 = agis_lookup_xml_data_rec.attribute45,
                attribute46 = agis_lookup_xml_data_rec.attribute46,
                attribute47 = agis_lookup_xml_data_rec.attribute47,
                attribute48 = agis_lookup_xml_data_rec.attribute48,
                attribute49 = agis_lookup_xml_data_rec.attribute49,
                attribute50 = agis_lookup_xml_data_rec.attribute50,
                attribute_sort_order = agis_lookup_xml_data_rec.attribute_sort_order,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                flex_value_meaning = agis_lookup_xml_data_rec.flex_value_meaning,
                description = agis_lookup_xml_data_rec.description,
                flex_value_set_name = agis_lookup_xml_data_rec.flex_value_set_name
            WHERE
                --CEN-8040 start
				--row_id = agis_lookup_xml_data_rec.row_id
				FLEX_VALUE_ID = agis_lookup_xml_data_rec.FLEX_VALUE_ID
				--CEN-8040 end
				;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;

	-- Insert
        INSERT INTO xxagis_value_set_values (
            row_id,
            flex_value_set_id,
            flex_value_id,
            flex_value,
            enabled_flag,
            start_date_active,
            end_date_active,
            summary_flag,
            parent_flex_value_low,
            parent_flex_value_high,
            structured_hierarchy_level,
            hierarchy_level,
            compiled_value_attributes,
            value_category,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            attribute16,
            attribute17,
            attribute18,
            attribute19,
            attribute20,
            attribute21,
            attribute22,
            attribute23,
            attribute24,
            attribute25,
            attribute26,
            attribute27,
            attribute28,
            attribute29,
            attribute30,
            attribute31,
            attribute32,
            attribute33,
            attribute34,
            attribute35,
            attribute36,
            attribute37,
            attribute38,
            attribute39,
            attribute40,
            attribute41,
            attribute42,
            attribute43,
            attribute44,
            attribute45,
            attribute46,
            attribute47,
            attribute48,
            attribute49,
            attribute50,
            attribute_sort_order,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            flex_value_meaning,
            description,
            flex_value_set_name
        )
            ( SELECT
                x.row_id,
                x.flex_value_set_id,
                x.flex_value_id,
                x.flex_value,
                x.enabled_flag,
                to_char(to_date(substr(x.start_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.summary_flag,
                x.parent_flex_value_low,
                x.parent_flex_value_high,
                x.structured_hierarchy_level,
                x.hierarchy_level,
                x.compiled_value_attributes,
                x.value_category,
                x.attribute1,
                x.attribute2,
                x.attribute3,
                x.attribute4,
                x.attribute5,
                x.attribute6,
                x.attribute7,
                x.attribute8,
                x.attribute9,
                x.attribute10,
                x.attribute11,
                x.attribute12,
                x.attribute13,
                x.attribute14,
                x.attribute15,
                x.attribute16,
                x.attribute17,
                x.attribute18,
                x.attribute19,
                x.attribute20,
                x.attribute21,
                x.attribute22,
                x.attribute23,
                x.attribute24,
                x.attribute25,
                x.attribute26,
                x.attribute27,
                x.attribute28,
                x.attribute29,
                x.attribute30,
                x.attribute31,
                x.attribute32,
                x.attribute33,
                x.attribute34,
                x.attribute35,
                x.attribute36,
                x.attribute37,
                x.attribute38,
                x.attribute39,
                x.attribute40,
                x.attribute41,
                x.attribute42,
                x.attribute43,
                x.attribute44,
                x.attribute45,
                x.attribute46,
                x.attribute47,
                x.attribute48,
                x.attribute49,
                x.attribute50,
                x.attribute_sort_order,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.flex_value_meaning,
                x.description,
                x.flex_value_set_name
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        row_id VARCHAR2(150) PATH './ROW_ID',
                        flex_value_set_id NUMBER PATH './FLEX_VALUE_SET_ID',
                        flex_value_id NUMBER PATH './FLEX_VALUE_ID',
                        flex_value VARCHAR2(150) PATH './FLEX_VALUE',
                        enabled_flag VARCHAR2(30) PATH './ENABLED_FLAG',
                        start_date_active VARCHAR2(240) PATH './START_DATE_ACTIVE',
                        end_date_active VARCHAR2(240) PATH './END_DATE_ACTIVE',
                        summary_flag VARCHAR2(30) PATH './SUMMARY_FLAG',
                        parent_flex_value_low VARCHAR2(150) PATH './PARENT_FLEX_VALUE_LOW',
                        parent_flex_value_high VARCHAR2(150) PATH './PARENT_FLEX_VALUE_HIGH',
                        structured_hierarchy_level VARCHAR2(240) PATH './STRUCTURED_HIERARCHY_LEVEL',
                        hierarchy_level VARCHAR2(240) PATH './HIERARCHY_LEVEL',
                        compiled_value_attributes VARCHAR2(240) PATH './COMPILED_VALUE_ATTRIBUTES',
                        value_category VARCHAR2(60) PATH './VALUE_CATEGORY',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        attribute6 VARCHAR2(240) PATH './ATTRIBUTE6',
                        attribute7 VARCHAR2(240) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(240) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(240) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(240) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(240) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(240) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(240) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(240) PATH './ATTRIBUTE14',
                        attribute15 VARCHAR2(240) PATH './ATTRIBUTE15',
                        attribute16 VARCHAR2(240) PATH './ATTRIBUTE16',
                        attribute17 VARCHAR2(240) PATH './ATTRIBUTE17',
                        attribute18 VARCHAR2(240) PATH './ATTRIBUTE18',
                        attribute19 VARCHAR2(240) PATH './ATTRIBUTE19',
                        attribute20 VARCHAR2(240) PATH './ATTRIBUTE20',
                        attribute21 VARCHAR2(240) PATH './ATTRIBUTE21',
                        attribute22 VARCHAR2(240) PATH './ATTRIBUTE22',
                        attribute23 VARCHAR2(240) PATH './ATTRIBUTE23',
                        attribute24 VARCHAR2(240) PATH './ATTRIBUTE24',
                        attribute25 VARCHAR2(240) PATH './ATTRIBUTE25',
                        attribute26 VARCHAR2(240) PATH './ATTRIBUTE26',
                        attribute27 VARCHAR2(240) PATH './ATTRIBUTE27',
                        attribute28 VARCHAR2(240) PATH './ATTRIBUTE28',
                        attribute29 VARCHAR2(240) PATH './ATTRIBUTE29',
                        attribute30 VARCHAR2(240) PATH './ATTRIBUTE30',
                        attribute31 VARCHAR2(240) PATH './ATTRIBUTE31',
                        attribute32 VARCHAR2(240) PATH './ATTRIBUTE32',
                        attribute33 VARCHAR2(240) PATH './ATTRIBUTE33',
                        attribute34 VARCHAR2(240) PATH './ATTRIBUTE34',
                        attribute35 VARCHAR2(240) PATH './ATTRIBUTE35',
                        attribute36 VARCHAR2(240) PATH './ATTRIBUTE36',
                        attribute37 VARCHAR2(240) PATH './ATTRIBUTE37',
                        attribute38 VARCHAR2(240) PATH './ATTRIBUTE38',
                        attribute39 VARCHAR2(240) PATH './ATTRIBUTE39',
                        attribute40 VARCHAR2(240) PATH './ATTRIBUTE40',
                        attribute41 VARCHAR2(240) PATH './ATTRIBUTE41',
                        attribute42 VARCHAR2(240) PATH './ATTRIBUTE42',
                        attribute43 VARCHAR2(240) PATH './ATTRIBUTE43',
                        attribute44 VARCHAR2(240) PATH './ATTRIBUTE44',
                        attribute45 VARCHAR2(240) PATH './ATTRIBUTE45',
                        attribute46 VARCHAR2(240) PATH './ATTRIBUTE46',
                        attribute47 VARCHAR2(240) PATH './ATTRIBUTE47',
                        attribute48 VARCHAR2(240) PATH './ATTRIBUTE48',
                        attribute49 VARCHAR2(240) PATH './ATTRIBUTE49',
                        attribute50 VARCHAR2(240) PATH './ATTRIBUTE50',
                        attribute_sort_order NUMBER PATH './ATTRIBUTE_SORT_ORDER',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(240) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(240) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(240) PATH './LAST_UPDATE_LOGIN',
                        flex_value_meaning VARCHAR2(240) PATH './FLEX_VALUE_MEANING',
                        description VARCHAR2(240) PATH './DESCRIPTION',
                        flex_value_set_name VARCHAR2(240) PATH './FLEX_VALUE_SET_NAME'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_VALUE_SET_VALUES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_value_set_values l
                    WHERE
                        --CEN-8040 starts
						--l.row_id = x.row_id
						l.FLEX_VALUE_ID = x.FLEX_VALUE_ID
						--CEN-8040 end
                )
            );

	--CEN-8040 starts
	DELETE FROM XXAGIS_VALUE_SET_VALUES 
	WHERE ROWID IN 
		(SELECT ROWID 
			FROM
				(SELECT ROWID,
						FLEX_VALUE_ID,
						ROW_NUMBER() OVER(PARTITION BY FLEX_VALUE_ID ORDER BY LAST_UPDATE_DATE DESC) ROWN 
					FROM XXAGIS_VALUE_SET_VALUES
				)
			WHERE ROWN > 1
		) ;
	COMMIT ;
	--CEN-8040 ends

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_value_set_values_insert_update',
            p_tracker => 'agis_value_set_values_insert_update', p_custom_err_info => 'EXCEPTION1 : agis_value_set_values_insert_update');
    END agis_value_set_values_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_CALENDAR_INSERT_UPDATE
	*
	*  Description:  Syncs GL Transaction Calendar BIP Report into gl_transaction_calendar table
	*
	**************************************************************************/

    PROCEDURE agis_gl_calendar_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            transaction_calendar_id gl_transaction_calendar.transaction_calendar_id%TYPE,
            name                    gl_transaction_calendar.name%TYPE,
            mon_business_day_flag   gl_transaction_calendar.mon_business_day_flag%TYPE,
            tue_business_day_flag   gl_transaction_calendar.tue_business_day_flag%TYPE,
            wed_business_day_flag   gl_transaction_calendar.wed_business_day_flag%TYPE,
            thu_business_day_flag   gl_transaction_calendar.thu_business_day_flag%TYPE,
            fri_business_day_flag   gl_transaction_calendar.fri_business_day_flag%TYPE,
            sat_business_day_flag   gl_transaction_calendar.sat_business_day_flag%TYPE,
            sun_business_day_flag   gl_transaction_calendar.sun_business_day_flag%TYPE,
            creation_date           gl_transaction_calendar.creation_date%TYPE,
            created_by              gl_transaction_calendar.created_by%TYPE,
            last_update_date        gl_transaction_calendar.last_update_date%TYPE,
            last_updated_by         gl_transaction_calendar.last_updated_by%TYPE,
            last_update_login       gl_transaction_calendar.last_update_login%TYPE,
            description             gl_transaction_calendar.description%TYPE,
            attribute1              gl_transaction_calendar.attribute1%TYPE,
            attribute2              gl_transaction_calendar.attribute2%TYPE,
            attribute3              gl_transaction_calendar.attribute3%TYPE,
            attribute4              gl_transaction_calendar.attribute4%TYPE,
            attribute5              gl_transaction_calendar.attribute5%TYPE,
            attribute6              gl_transaction_calendar.attribute6%TYPE,
            attribute7              gl_transaction_calendar.attribute7%TYPE,
            attribute8              gl_transaction_calendar.attribute8%TYPE,
            attribute9              gl_transaction_calendar.attribute9%TYPE,
            attribute10             gl_transaction_calendar.attribute10%TYPE,
            attribute11             gl_transaction_calendar.attribute11%TYPE,
            attribute12             gl_transaction_calendar.attribute12%TYPE,
            attribute13             gl_transaction_calendar.attribute13%TYPE,
            attribute14             gl_transaction_calendar.attribute14%TYPE,
            attribute15             gl_transaction_calendar.attribute15%TYPE,
            security_flag           gl_transaction_calendar.security_flag%TYPE
			  --,		  OBJECT_VERSION_NUMBER                gl_transaction_calendar.OBJECT_VERSION_NUMBER%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_calendar_insert_update', 'STATEMENT', 'Procedure running for report name: AGIS_GL_CALENDAR',
        'AGIS_GL_CALENDAR');

	--Update
        OPEN lcu_read_xml_data FOR ( ' SELECT
				 x.TRANSACTION_CALENDAR_ID
				,x.NAME
				,x.MON_BUSINESS_DAY_FLAG
				,x.TUE_BUSINESS_DAY_FLAG
				,x.WED_BUSINESS_DAY_FLAG
				,x.THU_BUSINESS_DAY_FLAG
				,x.FRI_BUSINESS_DAY_FLAG
				,x.SAT_BUSINESS_DAY_FLAG
				,x.SUN_BUSINESS_DAY_FLAG
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.DESCRIPTION
				,x.ATTRIBUTE1
				,x.ATTRIBUTE2
				,x.ATTRIBUTE3
				,x.ATTRIBUTE4
				,x.ATTRIBUTE5
				,x.ATTRIBUTE6
				,x.ATTRIBUTE7
				,x.ATTRIBUTE8
				,x.ATTRIBUTE9
				,x.ATTRIBUTE10
				,x.ATTRIBUTE11
				,x.ATTRIBUTE12
				,x.ATTRIBUTE13
				,x.ATTRIBUTE14
				,x.ATTRIBUTE15
				,x.SECURITY_FLAG

				FROM
				xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  TRANSACTION_CALENDAR_ID NUMBER PATH ''./TRANSACTION_CALENDAR_ID''
										  ,NAME VARCHAR2(150) PATH ''./NAME''
										  ,MON_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./MON_BUSINESS_DAY_FLAG''
										  ,TUE_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./TUE_BUSINESS_DAY_FLAG''
										  ,WED_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./WED_BUSINESS_DAY_FLAG''
										  ,THU_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./THU_BUSINESS_DAY_FLAG''
										  ,FRI_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./FRI_BUSINESS_DAY_FLAG''
										  ,SAT_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./SAT_BUSINESS_DAY_FLAG''
										  ,SUN_BUSINESS_DAY_FLAG VARCHAR2(150) PATH ''./SUN_BUSINESS_DAY_FLAG''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION''
										  ,ATTRIBUTE1 VARCHAR2(150) PATH ''./ATTRIBUTE1''
										  ,ATTRIBUTE2 VARCHAR2(150) PATH ''./ATTRIBUTE2''
										  ,ATTRIBUTE3 VARCHAR2(150) PATH ''./ATTRIBUTE3''
										  ,ATTRIBUTE4 VARCHAR2(150) PATH ''./ATTRIBUTE4''
										  ,ATTRIBUTE5 VARCHAR2(150) PATH ''./ATTRIBUTE5''
										  ,ATTRIBUTE6 VARCHAR2(150) PATH ''./ATTRIBUTE6''
										  ,ATTRIBUTE7 VARCHAR2(150) PATH ''./ATTRIBUTE7''
										  ,ATTRIBUTE8 VARCHAR2(150) PATH ''./ATTRIBUTE8''
										  ,ATTRIBUTE9 VARCHAR2(150) PATH ''./ATTRIBUTE9''
										  ,ATTRIBUTE10 VARCHAR2(150) PATH ''./ATTRIBUTE10''
										  ,ATTRIBUTE11 VARCHAR2(150) PATH ''./ATTRIBUTE11''
										  ,ATTRIBUTE12 VARCHAR2(150) PATH ''./ATTRIBUTE12''
										  ,ATTRIBUTE13 VARCHAR2(150) PATH ''./ATTRIBUTE13''
										  ,ATTRIBUTE14 VARCHAR2(150) PATH ''./ATTRIBUTE14''
										  ,ATTRIBUTE15 VARCHAR2(150) PATH ''./ATTRIBUTE15''
										  ,SECURITY_FLAG VARCHAR2(150) PATH ''./SECURITY_FLAG''

										  ) x	
				WHERE t.template_name LIKE ''AGIS_GL_CALENDAR''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND EXISTS (SELECT 1 FROM gl_transaction_calendar L WHERE L.TRANSACTION_CALENDAR_ID = x.TRANSACTION_CALENDAR_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE gl_transaction_calendar
            SET
                transaction_calendar_id = agis_lookup_xml_data_rec.transaction_calendar_id,
                name = agis_lookup_xml_data_rec.name,
                mon_business_day_flag = agis_lookup_xml_data_rec.mon_business_day_flag,
                tue_business_day_flag = agis_lookup_xml_data_rec.tue_business_day_flag,
                wed_business_day_flag = agis_lookup_xml_data_rec.wed_business_day_flag,
                thu_business_day_flag = agis_lookup_xml_data_rec.thu_business_day_flag,
                fri_business_day_flag = agis_lookup_xml_data_rec.fri_business_day_flag,
                sat_business_day_flag = agis_lookup_xml_data_rec.sat_business_day_flag,
                sun_business_day_flag = agis_lookup_xml_data_rec.sun_business_day_flag,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                description = agis_lookup_xml_data_rec.description,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                security_flag = agis_lookup_xml_data_rec.security_flag
            WHERE
                transaction_calendar_id = agis_lookup_xml_data_rec.transaction_calendar_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	 

	-- Insert
        INSERT INTO gl_transaction_calendar (
            transaction_calendar_id,
            name,
            mon_business_day_flag,
            tue_business_day_flag,
            wed_business_day_flag,
            thu_business_day_flag,
            fri_business_day_flag,
            sat_business_day_flag,
            sun_business_day_flag,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            description,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            security_flag
        )
            ( SELECT
                x.transaction_calendar_id,
                x.name,
                x.mon_business_day_flag,
                x.tue_business_day_flag,
                x.wed_business_day_flag,
                x.thu_business_day_flag,
                x.fri_business_day_flag,
                x.sat_business_day_flag,
                x.sun_business_day_flag,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.description,
                x.attribute1,
                x.attribute2,
                x.attribute3,
                x.attribute4,
                x.attribute5,
                x.attribute6,
                x.attribute7,
                x.attribute8,
                x.attribute9,
                x.attribute10,
                x.attribute11,
                x.attribute12,
                x.attribute13,
                x.attribute14,
                x.attribute15,
                x.security_flag
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        transaction_calendar_id NUMBER PATH './TRANSACTION_CALENDAR_ID',
                        name VARCHAR2(25) PATH './NAME',
                        mon_business_day_flag VARCHAR2(1) PATH './MON_BUSINESS_DAY_FLAG',
                        tue_business_day_flag VARCHAR2(1) PATH './TUE_BUSINESS_DAY_FLAG',
                        wed_business_day_flag VARCHAR2(1) PATH './WED_BUSINESS_DAY_FLAG',
                        thu_business_day_flag VARCHAR2(1) PATH './THU_BUSINESS_DAY_FLAG',
                        fri_business_day_flag VARCHAR2(1) PATH './FRI_BUSINESS_DAY_FLAG',
                        sat_business_day_flag VARCHAR2(1) PATH './SAT_BUSINESS_DAY_FLAG',
                        sun_business_day_flag VARCHAR2(1) PATH './SUN_BUSINESS_DAY_FLAG',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        description VARCHAR2(240) PATH './DESCRIPTION',
                        attribute1 VARCHAR2(150) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(150) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(150) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(150) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(150) PATH './ATTRIBUTE5',
                        attribute6 VARCHAR2(150) PATH './ATTRIBUTE6',
                        attribute7 VARCHAR2(150) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(150) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(150) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(150) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(150) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(150) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(150) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(150) PATH './ATTRIBUTE14',
                        attribute15 VARCHAR2(150) PATH './ATTRIBUTE15',
                        security_flag VARCHAR2(1) PATH './SECURITY_FLAG'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_GL_CALENDAR'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        gl_transaction_calendar l
                    WHERE
                        l.transaction_calendar_id = x.transaction_calendar_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_calendar_insert_update', p_tracker =>
            'agis_gl_calendar_insert_update', p_custom_err_info => 'EXCEPTION1 : agis_gl_calendar_insert_update');
    END agis_gl_calendar_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_DATES_INSERT_UPDATE
	*
	*  Description:  Syncs GL Transaction Dates BIP Report into GL_TRANSACTION_DATES table
	*
	**************************************************************************/

    PROCEDURE agis_gl_dates_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            transaction_calendar_id gl_transaction_dates.transaction_calendar_id%TYPE,
            transaction_date        gl_transaction_dates.transaction_date%TYPE,
            day_of_week             gl_transaction_dates.day_of_week%TYPE,
            business_day_flag       gl_transaction_dates.business_day_flag%TYPE,
            creation_date           gl_transaction_dates.creation_date%TYPE,
            created_by              gl_transaction_dates.created_by%TYPE,
            last_update_date        gl_transaction_dates.last_update_date%TYPE,
            last_updated_by         gl_transaction_dates.last_updated_by%TYPE,
            last_update_login       gl_transaction_dates.last_update_login%TYPE,
            attribute1              gl_transaction_dates.attribute1%TYPE,
            attribute2              gl_transaction_dates.attribute2%TYPE,
            attribute3              gl_transaction_dates.attribute3%TYPE,
            attribute4              gl_transaction_dates.attribute4%TYPE,
            attribute5              gl_transaction_dates.attribute5%TYPE,
            attribute6              gl_transaction_dates.attribute6%TYPE,
            attribute7              gl_transaction_dates.attribute7%TYPE,
            attribute8              gl_transaction_dates.attribute8%TYPE,
            attribute9              gl_transaction_dates.attribute9%TYPE,
            attribute10             gl_transaction_dates.attribute10%TYPE,
            attribute11             gl_transaction_dates.attribute11%TYPE,
            attribute12             gl_transaction_dates.attribute12%TYPE,
            attribute13             gl_transaction_dates.attribute13%TYPE,
            attribute14             gl_transaction_dates.attribute14%TYPE,
            attribute15             gl_transaction_dates.attribute15%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_dates_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_GL_DATES', 'AGIS_GL_DATES');

	----Update
        BEGIN  /* 3-27580827611 BEGIN and corrosponding Exception Section */
            OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.TRANSACTION_CALENDAR_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.TRANSACTION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.DAY_OF_WEEK
				,x.BUSINESS_DAY_FLAG
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.ATTRIBUTE1
				,x.ATTRIBUTE2
				,x.ATTRIBUTE3
				,x.ATTRIBUTE4
				,x.ATTRIBUTE5
				,x.ATTRIBUTE6
				,x.ATTRIBUTE7
				,x.ATTRIBUTE8
				,x.ATTRIBUTE9
				,x.ATTRIBUTE10
				,x.ATTRIBUTE11
				,x.ATTRIBUTE12
				,x.ATTRIBUTE13
				,x.ATTRIBUTE14
				,x.ATTRIBUTE15
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  TRANSACTION_CALENDAR_ID NUMBER PATH ''./TRANSACTION_CALENDAR_ID''
										  ,TRANSACTION_DATE VARCHAR2(240) PATH ''./TRANSACTION_DATE''
										  ,DAY_OF_WEEK VARCHAR2(240) PATH ''./DAY_OF_WEEK''
										  ,BUSINESS_DAY_FLAG VARCHAR2(240) PATH ''./BUSINESS_DAY_FLAG''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''
										  ,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''
										  ,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''
										  ,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''
										  ,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''
										  ,ATTRIBUTE6 VARCHAR2(240) PATH ''./ATTRIBUTE6''
										  ,ATTRIBUTE7 VARCHAR2(240) PATH ''./ATTRIBUTE7''
										  ,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8''
										  ,ATTRIBUTE9 VARCHAR2(240) PATH ''./ATTRIBUTE9''
										  ,ATTRIBUTE10 VARCHAR2(240) PATH ''./ATTRIBUTE10''
										  ,ATTRIBUTE11 VARCHAR2(240) PATH ''./ATTRIBUTE11''
										  ,ATTRIBUTE12 VARCHAR2(240) PATH ''./ATTRIBUTE12''
										  ,ATTRIBUTE13 VARCHAR2(240) PATH ''./ATTRIBUTE13''
										  ,ATTRIBUTE14 VARCHAR2(240) PATH ''./ATTRIBUTE14''
										  ,ATTRIBUTE15 VARCHAR2(240) PATH ''./ATTRIBUTE15''
										  ) x
				WHERE t.template_name LIKE ''AGIS_GL_DATES''
				AND t.USER_NAME= '''
                                         || p_user_name
                                         || '''
				AND  EXISTS (SELECT 1 FROM GL_TRANSACTION_DATES  L WHERE L.TRANSACTION_CALENDAR_ID = x.TRANSACTION_CALENDAR_ID
				AND  L.TRANSACTION_DATE=TO_CHAR(TO_DATE(SUBSTR(x.TRANSACTION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY''))' );

            LOOP
                FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
                UPDATE gl_transaction_dates
                SET
                    transaction_calendar_id = agis_lookup_xml_data_rec.transaction_calendar_id,
                    transaction_date = agis_lookup_xml_data_rec.transaction_date,
                    day_of_week = agis_lookup_xml_data_rec.day_of_week,
                    business_day_flag = agis_lookup_xml_data_rec.business_day_flag,
                    creation_date = agis_lookup_xml_data_rec.creation_date,
                    created_by = agis_lookup_xml_data_rec.created_by,
                    last_update_date = agis_lookup_xml_data_rec.last_update_date,
                    last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                    last_update_login = agis_lookup_xml_data_rec.last_update_login,
                    attribute1 = agis_lookup_xml_data_rec.attribute1,
                    attribute2 = agis_lookup_xml_data_rec.attribute2,
                    attribute3 = agis_lookup_xml_data_rec.attribute3,
                    attribute4 = agis_lookup_xml_data_rec.attribute4,
                    attribute5 = agis_lookup_xml_data_rec.attribute5,
                    attribute6 = agis_lookup_xml_data_rec.attribute6,
                    attribute7 = agis_lookup_xml_data_rec.attribute7,
                    attribute8 = agis_lookup_xml_data_rec.attribute8,
                    attribute9 = agis_lookup_xml_data_rec.attribute9,
                    attribute10 = agis_lookup_xml_data_rec.attribute10,
                    attribute11 = agis_lookup_xml_data_rec.attribute11,
                    attribute12 = agis_lookup_xml_data_rec.attribute12,
                    attribute13 = agis_lookup_xml_data_rec.attribute13,
                    attribute14 = agis_lookup_xml_data_rec.attribute14,
                    attribute15 = agis_lookup_xml_data_rec.attribute15
                WHERE
                        transaction_calendar_id = agis_lookup_xml_data_rec.transaction_calendar_id
					--AND transaction_date = to_char(to_date(substr(agis_lookup_xml_data_rec.transaction_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'); -- 3-27580827611 Commented
                    AND trunc(transaction_date) = agis_lookup_xml_data_rec.transaction_date;-- 3-27580827611 Added

                EXIT WHEN lcu_read_xml_data%notfound;
            END LOOP;

            CLOSE lcu_read_xml_data;
        EXCEPTION /* 3-27580827611 Exception Section */
            WHEN OTHERS THEN
                oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_dates_insert_update', p_tracker =>
                'lcu_read_xml_data', p_custom_err_info => 'EXCEPTION1 : lcu_read_xml_data');
        END;
	-- Insert
        BEGIN /* 3-27580827611 BEGIN and corrosponding Exception Section */
            INSERT INTO gl_transaction_dates (
                transaction_calendar_id,
                transaction_date,
                day_of_week,
                business_day_flag,
                creation_date,
                created_by,
                last_update_date,
                last_updated_by,
                last_update_login,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                attribute6,
                attribute7,
                attribute8,
                attribute9,
                attribute10,
                attribute11,
                attribute12,
                attribute13,
                attribute14,
                attribute15
            )
                ( SELECT
                    x.transaction_calendar_id,
                    to_char(to_date(substr(x.transaction_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                    x.day_of_week,
                    x.business_day_flag,
                    to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                    x.created_by,
                    to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                    x.last_updated_by,
                    x.last_update_login,
                    x.attribute1,
                    x.attribute2,
                    x.attribute3,
                    x.attribute4,
                    x.attribute5,
                    x.attribute6,
                    x.attribute7,
                    x.attribute8,
                    x.attribute9,
                    x.attribute10,
                    x.attribute11,
                    x.attribute12,
                    x.attribute13,
                    x.attribute14,
                    x.attribute15
                FROM
                    xxagis_from_base64 t,
                    XMLTABLE ( '//G_1'
                            PASSING xmltype(t.clobdata)
                        COLUMNS
                            transaction_calendar_id NUMBER PATH './TRANSACTION_CALENDAR_ID',
                            transaction_date VARCHAR2(240) PATH './TRANSACTION_DATE',
                            day_of_week VARCHAR2(240) PATH './DAY_OF_WEEK',
                            business_day_flag VARCHAR2(240) PATH './BUSINESS_DAY_FLAG',
                            creation_date VARCHAR2(240) PATH './CREATION_DATE',
                            created_by VARCHAR2(300) PATH './CREATED_BY',
                            last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                            last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                            last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                            attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                            attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                            attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                            attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                            attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                            attribute6 VARCHAR2(240) PATH './ATTRIBUTE6',
                            attribute7 VARCHAR2(240) PATH './ATTRIBUTE7',
                            attribute8 VARCHAR2(240) PATH './ATTRIBUTE8',
                            attribute9 VARCHAR2(240) PATH './ATTRIBUTE9',
                            attribute10 VARCHAR2(240) PATH './ATTRIBUTE10',
                            attribute11 VARCHAR2(240) PATH './ATTRIBUTE11',
                            attribute12 VARCHAR2(240) PATH './ATTRIBUTE12',
                            attribute13 VARCHAR2(240) PATH './ATTRIBUTE13',
                            attribute14 VARCHAR2(240) PATH './ATTRIBUTE14',
                            attribute15 VARCHAR2(240) PATH './ATTRIBUTE15'
                    )                  x
                WHERE
                    t.template_name LIKE 'AGIS_GL_DATES'
                    AND t.user_name = p_user_name
                    AND NOT EXISTS (
                        SELECT
                            1
                        FROM
                            gl_transaction_dates l
                        WHERE
                                l.transaction_calendar_id = x.transaction_calendar_id
                            AND l.transaction_date = to_char(to_date(substr(x.transaction_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY')
							--AND transaction_date = to_char(to_date(substr(agis_lookup_xml_data_rec.transaction_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'); -- 3-27580827611 Commented
                            AND trunc(transaction_date) = agis_lookup_xml_data_rec.transaction_date -- 3-27580827611 Added
                    )
                );

        EXCEPTION /* 3-27580827611 Exception Section */
            WHEN OTHERS THEN
                oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_dates_insert_update', p_tracker =>
                'INSERT INTO gl_transaction_dates', p_custom_err_info => 'EXCEPTION2 : INSERT INTO gl_transaction_dates');
        END;

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_dates_insert_update', p_tracker =>
            'agis_gl_dates_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_gl_dates_insert_update');
    END agis_gl_dates_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_SYNC_USER_ROLE
	*
	*  Description:  Syncs User Roles Report into XXAGIS_USER_ROLE_MAP table
	*
	**************************************************************************/

    PROCEDURE agis_sync_user_role (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            role_name                    xxagis_user_role_map.role_name%TYPE,
            interco_org_id               xxagis_user_role_map.interco_org_id%TYPE,
            username                     xxagis_user_role_map.username%TYPE,
            user_role_data_assignment_id xxagis_user_role_map.user_role_data_assignment_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        BEGIN
            DELETE FROM xxagis_user_role_map
            WHERE
                username LIKE p_user_name;

        END;
        writetolog('xxagis_utility_pkg', 'agis_sync_user_role', 'STATEMENT', 'Procedure running for report name: USER_ROLE_REPORT USERNAME:' ||
        p_user_name, 'USER_ROLE_REPORT');

	 -- Insert
        INSERT INTO xxagis_user_role_map (
            role_name,
            interco_org_id,
            username,
            user_role_data_assignment_id
        )
            ( SELECT
                x.role_name,
                x.interco_org_id,
                x.username,
                x.user_role_data_assignment_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        role_name VARCHAR2(150) PATH './ROLE_NAME',
                        interco_org_id NUMBER PATH './INTERCO_ORG_ID',
                        username VARCHAR2(150) PATH './USERNAME',
                        user_role_data_assignment_id NUMBER PATH './USER_ROLE_DATA_ASSIGNMENT_ID'
                )                  x
            WHERE
                    t.template_name = 'USER_ROLE_REPORT'
                AND user_name = 'XXCUS'
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_user_role_map l
                    WHERE
                        l.user_role_data_assignment_id = x.user_role_data_assignment_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_sync_user_role', p_tracker =>
            'agis_sync_user_role', p_custom_err_info => 'EXCEPTION3 : agis_sync_user_role');
    END agis_sync_user_role;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_DATES_INSERT_UPDATE
	*
	*  Description:  Syncs System Options BIP Report into XXAGIS_FUN_SYSTEM_OPTIONS table
	*
	**************************************************************************/

    PROCEDURE agis_system_options_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            system_option_id           xxagis_fun_system_options.system_option_id%TYPE,
            inteco_calendar            xxagis_fun_system_options.inteco_calendar%TYPE,
            creation_date              xxagis_fun_system_options.creation_date%TYPE,
            created_by                 xxagis_fun_system_options.created_by%TYPE,
            last_update_date           xxagis_fun_system_options.last_update_date%TYPE,
            last_updated_by            xxagis_fun_system_options.last_updated_by%TYPE,
            last_update_login          xxagis_fun_system_options.last_update_login%TYPE,
            object_version_number      xxagis_fun_system_options.object_version_number%TYPE,
            default_currency           xxagis_fun_system_options.default_currency%TYPE,
            min_trx_amt                xxagis_fun_system_options.min_trx_amt%TYPE,
            min_trx_amt_currency       xxagis_fun_system_options.min_trx_amt_currency%TYPE,
            subledger_interco_currency xxagis_fun_system_options.subledger_interco_currency%TYPE,
            exchg_rate_type            xxagis_fun_system_options.exchg_rate_type%TYPE,
            numbering_type             xxagis_fun_system_options.numbering_type%TYPE,
            allow_reject_flag          xxagis_fun_system_options.allow_reject_flag%TYPE,
            gl_batch_flag              xxagis_fun_system_options.gl_batch_flag%TYPE,
            apar_batch_flag            xxagis_fun_system_options.apar_batch_flag%TYPE,
            attribute_category         xxagis_fun_system_options.attribute_category%TYPE,
            default_ar_trx_type_id     xxagis_fun_system_options.default_ar_trx_type_id%TYPE,
            default_memo_line_id       xxagis_fun_system_options.default_memo_line_id%TYPE,
            seed_data_source           xxagis_fun_system_options.seed_data_source%TYPE,
            default_trx_type_id        xxagis_fun_system_options.default_trx_type_id%TYPE,
            inteco_period_type         xxagis_fun_system_options.inteco_period_type%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_dates_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_SYSTEM_OPTIONS',
        'AGIS_SYSTEM_OPTIONS');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.SYSTEM_OPTION_ID
				,x.INTECO_CALENDAR
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.OBJECT_VERSION_NUMBER
				,x.DEFAULT_CURRENCY
				,x.MIN_TRX_AMT
				,x.MIN_TRX_AMT_CURRENCY
				,x.SUBLEDGER_INTERCO_CURRENCY
				,x.EXCHG_RATE_TYPE
				,x.NUMBERING_TYPE
				,x.ALLOW_REJECT_FLAG
				,x.GL_BATCH_FLAG
				,x.APAR_BATCH_FLAG
				,x.ATTRIBUTE_CATEGORY
				,x.DEFAULT_AR_TRX_TYPE_ID
				,x.DEFAULT_MEMO_LINE_ID
				,x.SEED_DATA_SOURCE
				,x.DEFAULT_TRX_TYPE_ID  
				,x.INTECO_PERIOD_TYPE
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  SYSTEM_OPTION_ID NUMBER PATH ''./SYSTEM_OPTION_ID''
										  ,INTECO_CALENDAR VARCHAR2(240) PATH ''./INTECO_CALENDAR''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER''
										  ,DEFAULT_CURRENCY VARCHAR2(240) PATH ''./DEFAULT_CURRENCY''
										  ,MIN_TRX_AMT NUMBER PATH ''./MIN_TRX_AMT''
										  ,MIN_TRX_AMT_CURRENCY VARCHAR2(240) PATH ''./MIN_TRX_AMT_CURRENCY''
										  ,SUBLEDGER_INTERCO_CURRENCY VARCHAR2(240) PATH ''./SUBLEDGER_INTERCO_CURRENCY''
										  ,EXCHG_RATE_TYPE VARCHAR2(240) PATH ''./EXCHG_RATE_TYPE''
										  ,NUMBERING_TYPE VARCHAR2(240) PATH ''./NUMBERING_TYPE''
										  ,ALLOW_REJECT_FLAG VARCHAR2(240) PATH ''./ALLOW_REJECT_FLAG''
										  ,GL_BATCH_FLAG VARCHAR2(240) PATH ''./GL_BATCH_FLAG''
										  ,APAR_BATCH_FLAG VARCHAR2(240) PATH ''./APAR_BATCH_FLAG''
										  ,ATTRIBUTE_CATEGORY VARCHAR2(240) PATH ''./ATTRIBUTE_CATEGORY''
										  ,DEFAULT_AR_TRX_TYPE_ID NUMBER PATH ''./DEFAULT_AR_TRX_TYPE_ID''
										  ,DEFAULT_MEMO_LINE_ID NUMBER PATH ''./DEFAULT_MEMO_LINE_ID''
										  ,SEED_DATA_SOURCE VARCHAR2(240) PATH ''./SEED_DATA_SOURCE''
										  ,DEFAULT_TRX_TYPE_ID   NUMBER PATH ''./DEFAULT_TRX_TYPE_ID  ''
										  ,INTECO_PERIOD_TYPE VARCHAR2(240) PATH ''./INTECO_PERIOD_TYPE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_SYSTEM_OPTIONS''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_FUN_SYSTEM_OPTIONS  L WHERE L.SYSTEM_OPTION_ID = x.SYSTEM_OPTION_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_fun_system_options
            SET
                system_option_id = agis_lookup_xml_data_rec.system_option_id,
                inteco_calendar = agis_lookup_xml_data_rec.inteco_calendar,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                default_currency = agis_lookup_xml_data_rec.default_currency,
                min_trx_amt = agis_lookup_xml_data_rec.min_trx_amt,
                min_trx_amt_currency = agis_lookup_xml_data_rec.min_trx_amt_currency,
                subledger_interco_currency = agis_lookup_xml_data_rec.subledger_interco_currency,
                exchg_rate_type = agis_lookup_xml_data_rec.exchg_rate_type,
                numbering_type = agis_lookup_xml_data_rec.numbering_type,
                allow_reject_flag = agis_lookup_xml_data_rec.allow_reject_flag,
                gl_batch_flag = agis_lookup_xml_data_rec.gl_batch_flag,
                apar_batch_flag = agis_lookup_xml_data_rec.apar_batch_flag,
                attribute_category = agis_lookup_xml_data_rec.attribute_category,
                default_ar_trx_type_id = agis_lookup_xml_data_rec.default_ar_trx_type_id,
                default_memo_line_id = agis_lookup_xml_data_rec.default_memo_line_id,
                seed_data_source = agis_lookup_xml_data_rec.seed_data_source,
                default_trx_type_id = agis_lookup_xml_data_rec.default_trx_type_id,
                inteco_period_type = agis_lookup_xml_data_rec.inteco_period_type
            WHERE
                system_option_id = agis_lookup_xml_data_rec.system_option_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_fun_system_options (
            system_option_id,
            inteco_calendar,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            object_version_number,
            default_currency,
            min_trx_amt,
            min_trx_amt_currency,
            subledger_interco_currency,
            exchg_rate_type,
            numbering_type,
            allow_reject_flag,
            gl_batch_flag,
            apar_batch_flag,
            attribute_category,
            default_ar_trx_type_id,
            default_memo_line_id,
            seed_data_source,
            default_trx_type_id,
            inteco_period_type
        )
            ( SELECT
                x.system_option_id,
                x.inteco_calendar,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.object_version_number,
                x.default_currency,
                x.min_trx_amt,
                x.min_trx_amt_currency,
                x.subledger_interco_currency,
                x.exchg_rate_type,
                x.numbering_type,
                x.allow_reject_flag,
                x.gl_batch_flag,
                x.apar_batch_flag,
                x.attribute_category,
                x.default_ar_trx_type_id,
                x.default_memo_line_id,
                x.seed_data_source,
                x.default_trx_type_id,
                x.inteco_period_type
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        system_option_id NUMBER PATH './SYSTEM_OPTION_ID',
                        inteco_calendar VARCHAR2(240) PATH './INTECO_CALENDAR',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        default_currency VARCHAR2(240) PATH './DEFAULT_CURRENCY',
                        min_trx_amt NUMBER PATH './MIN_TRX_AMT',
                        min_trx_amt_currency VARCHAR2(240) PATH './MIN_TRX_AMT_CURRENCY',
                        subledger_interco_currency VARCHAR2(240) PATH './SUBLEDGER_INTERCO_CURRENCY',
                        exchg_rate_type VARCHAR2(240) PATH './EXCHG_RATE_TYPE',
                        numbering_type VARCHAR2(240) PATH './NUMBERING_TYPE',
                        allow_reject_flag VARCHAR2(240) PATH './ALLOW_REJECT_FLAG',
                        gl_batch_flag VARCHAR2(240) PATH './GL_BATCH_FLAG',
                        apar_batch_flag VARCHAR2(240) PATH './APAR_BATCH_FLAG',
                        attribute_category VARCHAR2(240) PATH './ATTRIBUTE_CATEGORY',
                        default_ar_trx_type_id NUMBER PATH './DEFAULT_AR_TRX_TYPE_ID',
                        default_memo_line_id NUMBER PATH './DEFAULT_MEMO_LINE_ID',
                        seed_data_source VARCHAR2(240) PATH './SEED_DATA_SOURCE',
                        default_trx_type_id NUMBER PATH './DEFAULT_TRX_TYPE_ID',
                        inteco_period_type VARCHAR2(240) PATH './INTECO_PERIOD_TYPE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_SYSTEM_OPTIONS'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_fun_system_options l
                    WHERE
                        l.system_option_id = x.system_option_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_system_options_insert_update',
            p_tracker => 'agis_system_options_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_system_options_insert_update');
    END agis_system_options_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_PERIOD_STATUSES_INSERT_UPDATE
	*
	*  Description:  Syncs System Options BIP Report into XXAGIS_FUN_PERIOD_STATUSES table
	*
	**************************************************************************/

    PROCEDURE agis_period_statuses_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            period_name           xxagis_fun_period_statuses.period_name%TYPE,
            inteco_calendar       xxagis_fun_period_statuses.inteco_calendar%TYPE,
            creation_date         xxagis_fun_period_statuses.creation_date%TYPE,
            created_by            xxagis_fun_period_statuses.created_by%TYPE,
            last_update_date      xxagis_fun_period_statuses.last_update_date%TYPE,
            last_updated_by       xxagis_fun_period_statuses.last_updated_by%TYPE,
            last_update_login     xxagis_fun_period_statuses.last_update_login%TYPE,
            object_version_number xxagis_fun_period_statuses.object_version_number%TYPE,
            period_year           xxagis_fun_period_statuses.period_year%TYPE,
            start_date            xxagis_fun_period_statuses.start_date%TYPE,
            end_date              xxagis_fun_period_statuses.end_date%TYPE,
            year_start_date       xxagis_fun_period_statuses.year_start_date%TYPE,
            quarter_start_date    xxagis_fun_period_statuses.quarter_start_date%TYPE,
            status                xxagis_fun_period_statuses.status%TYPE,
            trx_type_id           xxagis_fun_period_statuses.trx_type_id%TYPE,
            period_num            xxagis_fun_period_statuses.period_num%TYPE,
            inteco_period_type    xxagis_fun_period_statuses.inteco_period_type%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_dates_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_PERIOD_STATUSES',
        'AGIS_PERIOD_STATUSES');

	----Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PERIOD_NAME
				,x.INTECO_CALENDAR
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.OBJECT_VERSION_NUMBER
				,x.PERIOD_YEAR
				,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.YEAR_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.QUARTER_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.STATUS
				,x.TRX_TYPE_ID
				,x.PERIOD_NUM
				,x.INTECO_PERIOD_TYPE
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PERIOD_NAME VARCHAR2(240) PATH ''./PERIOD_NAME''
										  ,INTECO_CALENDAR VARCHAR2(240) PATH ''./INTECO_CALENDAR''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER''
										  ,PERIOD_YEAR VARCHAR2(240) PATH ''./PERIOD_YEAR''
										  ,START_DATE VARCHAR2(240) PATH ''./START_DATE''
										  ,END_DATE VARCHAR2(240) PATH ''./END_DATE''
										  ,YEAR_START_DATE VARCHAR2(240) PATH ''./YEAR_START_DATE''
										  ,QUARTER_START_DATE VARCHAR2(240) PATH ''./QUARTER_START_DATE''
										  ,STATUS VARCHAR2(240) PATH ''./STATUS''
										  ,TRX_TYPE_ID NUMBER PATH ''./TRX_TYPE_ID''
										  ,PERIOD_NUM NUMBER PATH ''./PERIOD_NUM''
										  ,INTECO_PERIOD_TYPE VARCHAR2(240) PATH ''./INTECO_PERIOD_TYPE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_PERIOD_STATUSES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_FUN_PERIOD_STATUSES  L WHERE L.PERIOD_NAME = x.PERIOD_NAME
																		AND L.TRX_TYPE_ID=x.TRX_TYPE_ID
																		AND L.INTECO_CALENDAR=x.INTECO_CALENDAR
																		AND L.INTECO_PERIOD_TYPE=x.INTECO_PERIOD_TYPE)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_fun_period_statuses
            SET
                period_name = agis_lookup_xml_data_rec.period_name,
                inteco_calendar = agis_lookup_xml_data_rec.inteco_calendar,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                period_year = agis_lookup_xml_data_rec.period_year,
                start_date = agis_lookup_xml_data_rec.start_date,
                end_date = agis_lookup_xml_data_rec.end_date,
                year_start_date = agis_lookup_xml_data_rec.year_start_date,
                quarter_start_date = agis_lookup_xml_data_rec.quarter_start_date,
                status = agis_lookup_xml_data_rec.status,
                trx_type_id = agis_lookup_xml_data_rec.trx_type_id,
                period_num = agis_lookup_xml_data_rec.period_num,
                inteco_period_type = agis_lookup_xml_data_rec.inteco_period_type
            WHERE
                    period_name = agis_lookup_xml_data_rec.period_name
                AND trx_type_id = agis_lookup_xml_data_rec.trx_type_id
                AND inteco_calendar = agis_lookup_xml_data_rec.inteco_calendar
                AND inteco_period_type = agis_lookup_xml_data_rec.inteco_period_type;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_fun_period_statuses (
            period_name,
            inteco_calendar,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            object_version_number,
            period_year,
            start_date,
            end_date,
            year_start_date,
            quarter_start_date,
            status,
            trx_type_id,
            period_num,
            inteco_period_type
        )
            ( SELECT
                x.period_name,
                x.inteco_calendar,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.object_version_number,
                x.period_year,
                to_char(to_date(substr(x.start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.year_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.quarter_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.status,
                x.trx_type_id,
                x.period_num,
                x.inteco_period_type
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        period_name VARCHAR2(240) PATH './PERIOD_NAME',
                        inteco_calendar VARCHAR2(240) PATH './INTECO_CALENDAR',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        period_year VARCHAR2(240) PATH './PERIOD_YEAR',
                        start_date VARCHAR2(240) PATH './START_DATE',
                        end_date VARCHAR2(240) PATH './END_DATE',
                        year_start_date VARCHAR2(240) PATH './YEAR_START_DATE',
                        quarter_start_date VARCHAR2(240) PATH './QUARTER_START_DATE',
                        status VARCHAR2(240) PATH './STATUS',
                        trx_type_id NUMBER PATH './TRX_TYPE_ID',
                        period_num NUMBER PATH './PERIOD_NUM',
                        inteco_period_type VARCHAR2(240) PATH './INTECO_PERIOD_TYPE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_PERIOD_STATUSES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_fun_period_statuses l
                    WHERE
                            l.period_name = x.period_name
                        AND l.trx_type_id = x.trx_type_id
                        AND l.inteco_calendar = x.inteco_calendar
                        AND l.inteco_period_type = x.inteco_period_type
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_period_statuses_insert_update',
            p_tracker => 'agis_period_statuses_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_period_statuses_insert_update');
    END agis_period_statuses_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_PERIOD_STATUSES_INSERT_UPDATE
	*
	*  Description:  Syncs GL Period Statuses BIP Report into GL_PERIOD_STATUSES table
	*
	**************************************************************************/

    PROCEDURE agis_gl_period_statuses_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            application_id                gl_period_statuses.application_id%TYPE,
            set_of_books_id               gl_period_statuses.set_of_books_id%TYPE,
            creation_date                 gl_period_statuses.creation_date%TYPE,
            created_by                    gl_period_statuses.created_by%TYPE,
            last_update_date              gl_period_statuses.last_update_date%TYPE,
            last_updated_by               gl_period_statuses.last_updated_by%TYPE,
            last_update_login             gl_period_statuses.last_update_login%TYPE,
            closing_status                gl_period_statuses.closing_status%TYPE,
            period_year                   gl_period_statuses.period_year%TYPE,
            start_date                    gl_period_statuses.start_date%TYPE,
            end_date                      gl_period_statuses.end_date%TYPE,
            year_start_date               gl_period_statuses.year_start_date%TYPE,
            quarter_start_date            gl_period_statuses.quarter_start_date%TYPE,
            quarter_num                   gl_period_statuses.quarter_num%TYPE,
            period_type                   gl_period_statuses.period_type%TYPE,
            period_num                    gl_period_statuses.period_num%TYPE,
            effective_period_num          gl_period_statuses.effective_period_num%TYPE,
            period_name                   gl_period_statuses.period_name%TYPE,
            adjustment_period_flag        gl_period_statuses.adjustment_period_flag%TYPE,
            attribute1                    gl_period_statuses.attribute1%TYPE,
            attribute2                    gl_period_statuses.attribute2%TYPE,
            attribute3                    gl_period_statuses.attribute3%TYPE,
            attribute4                    gl_period_statuses.attribute4%TYPE,
            attribute5                    gl_period_statuses.attribute5%TYPE,
            context                       gl_period_statuses.context%TYPE,
            elimination_confirmed_flag    gl_period_statuses.elimination_confirmed_flag%TYPE,
            chronological_seq_status_code gl_period_statuses.chronological_seq_status_code%TYPE,
            ledger_id                     gl_period_statuses.ledger_id%TYPE,
            migration_status_code         gl_period_statuses.migration_status_code%TYPE,
            track_bc_ytd_flag             gl_period_statuses.track_bc_ytd_flag%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_period_statuses_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_GL_PERIOD_STATUSES',
        'AGIS_GL_PERIOD_STATUSES');

	----Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.APPLICATION_ID
				,x.SET_OF_BOOKS_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.CLOSING_STATUS
				,x.PERIOD_YEAR
				,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.YEAR_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.QUARTER_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.QUARTER_NUM
				,x.PERIOD_TYPE
				,x.PERIOD_NUM
				,x.EFFECTIVE_PERIOD_NUM
				,PERIOD_NAME                        
				,ADJUSTMENT_PERIOD_FLAG              
				,ATTRIBUTE1                           
				,ATTRIBUTE2                           
				,ATTRIBUTE3                           
				,ATTRIBUTE4                           
				,ATTRIBUTE5                           
				,CONTEXT                              
				,ELIMINATION_CONFIRMED_FLAG           
				,CHRONOLOGICAL_SEQ_STATUS_CODE        
				,LEDGER_ID                            
				,MIGRATION_STATUS_CODE                
				,TRACK_BC_YTD_FLAG                    

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  APPLICATION_ID NUMBER PATH ''./APPLICATION_ID''
										  ,SET_OF_BOOKS_ID NUMBER PATH ''./SET_OF_BOOKS_ID''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,CLOSING_STATUS VARCHAR(15) PATH ''./CLOSING_STATUS''
										  ,PERIOD_YEAR NUMBER PATH ''./PERIOD_YEAR''
										  ,START_DATE VARCHAR2(240) PATH ''./START_DATE''
										  ,END_DATE VARCHAR2(240) PATH ''./END_DATE''
										  ,YEAR_START_DATE VARCHAR2(240) PATH ''./YEAR_START_DATE''
										  ,QUARTER_START_DATE VARCHAR2(240) PATH ''./QUARTER_START_DATE''
										  ,QUARTER_NUM NUMBER PATH ''./QUARTER_NUM''
										  ,PERIOD_TYPE VARCHAR2(240) PATH ''./PERIOD_TYPE''
										  ,PERIOD_NUM NUMBER PATH ''./PERIOD_NUM''
										  ,EFFECTIVE_PERIOD_NUM NUMBER PATH ''./EFFECTIVE_PERIOD_NUM''
										  ,PERIOD_NAME VARCHAR2(240) PATH ''./PERIOD_NAME''                        
										  ,ADJUSTMENT_PERIOD_FLAG VARCHAR2(240) PATH ''./ADJUSTMENT_PERIOD_FLAG''              
										  ,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''                           
										  ,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''                           
										  ,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''                           
										  ,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''                           
										  ,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''                           
										  ,CONTEXT VARCHAR2(240) PATH ''./CONTEXT''                              
										  ,ELIMINATION_CONFIRMED_FLAG VARCHAR2(240) PATH ''./ELIMINATION_CONFIRMED_FLAG''           
										  ,CHRONOLOGICAL_SEQ_STATUS_CODE VARCHAR2(240) PATH ''./CHRONOLOGICAL_SEQ_STATUS_CODE''        
										  ,LEDGER_ID NUMBER PATH ''./LEDGER_ID''                            
										  ,MIGRATION_STATUS_CODE VARCHAR2(240) PATH ''./MIGRATION_STATUS_CODE''                
										  ,TRACK_BC_YTD_FLAG VARCHAR2(240) PATH ''./TRACK_BC_YTD_FLAG''  
										  ) x
				WHERE t.template_name LIKE ''AGIS_GL_PERIOD_STATUSES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM GL_PERIOD_STATUSES  L WHERE L.APPLICATION_ID = x.APPLICATION_ID
																		AND L.PERIOD_NAME= x.PERIOD_NAME
																		AND L.LEDGER_ID= x.LEDGER_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE gl_period_statuses
            SET
                application_id = agis_lookup_xml_data_rec.application_id,
                set_of_books_id = agis_lookup_xml_data_rec.set_of_books_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                closing_status = agis_lookup_xml_data_rec.closing_status,
                period_year = agis_lookup_xml_data_rec.period_year,
                start_date = agis_lookup_xml_data_rec.start_date,
                end_date = agis_lookup_xml_data_rec.end_date,
                year_start_date = agis_lookup_xml_data_rec.year_start_date,
                quarter_start_date = agis_lookup_xml_data_rec.quarter_start_date,
                quarter_num = agis_lookup_xml_data_rec.quarter_num,
                period_type = agis_lookup_xml_data_rec.period_type,
                period_num = agis_lookup_xml_data_rec.period_num,
                effective_period_num = agis_lookup_xml_data_rec.effective_period_num,
                period_name = agis_lookup_xml_data_rec.period_name,
                adjustment_period_flag = agis_lookup_xml_data_rec.adjustment_period_flag,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                context = agis_lookup_xml_data_rec.context,
                elimination_confirmed_flag = agis_lookup_xml_data_rec.elimination_confirmed_flag,
                chronological_seq_status_code = agis_lookup_xml_data_rec.chronological_seq_status_code,
                ledger_id = agis_lookup_xml_data_rec.ledger_id,
                migration_status_code = agis_lookup_xml_data_rec.migration_status_code,
                track_bc_ytd_flag = agis_lookup_xml_data_rec.track_bc_ytd_flag
            WHERE
                    application_id = agis_lookup_xml_data_rec.application_id
                AND period_name = agis_lookup_xml_data_rec.period_name
                AND ledger_id = agis_lookup_xml_data_rec.ledger_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO gl_period_statuses (
            application_id,
            set_of_books_id,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            closing_status,
            period_year,
            start_date,
            end_date,
            year_start_date,
            quarter_start_date,
            quarter_num,
            period_type,
            period_num,
            effective_period_num,
            period_name,
            adjustment_period_flag,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            context,
            elimination_confirmed_flag,
            chronological_seq_status_code,
            ledger_id,
            migration_status_code,
            track_bc_ytd_flag
        )
            ( SELECT
                x.application_id,
                x.set_of_books_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.closing_status,
                x.period_year,
                to_char(to_date(substr(x.start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.year_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.quarter_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.quarter_num,
                x.period_type,
                x.period_num,
                x.effective_period_num,
                period_name,
                adjustment_period_flag,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                context,
                elimination_confirmed_flag,
                chronological_seq_status_code,
                ledger_id,
                migration_status_code,
                track_bc_ytd_flag
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        application_id NUMBER PATH './APPLICATION_ID',
                        set_of_books_id NUMBER PATH './SET_OF_BOOKS_ID',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        closing_status VARCHAR(15) PATH './CLOSING_STATUS',
                        period_year NUMBER PATH './PERIOD_YEAR',
                        start_date VARCHAR2(240) PATH './START_DATE',
                        end_date VARCHAR2(240) PATH './END_DATE',
                        year_start_date VARCHAR2(240) PATH './YEAR_START_DATE',
                        quarter_start_date VARCHAR2(240) PATH './QUARTER_START_DATE',
                        quarter_num NUMBER PATH './QUARTER_NUM',
                        period_type VARCHAR2(240) PATH './PERIOD_TYPE',
                        period_num NUMBER PATH './PERIOD_NUM',
                        effective_period_num NUMBER PATH './EFFECTIVE_PERIOD_NUM',
                        period_name VARCHAR2(240) PATH './PERIOD_NAME',
                        adjustment_period_flag VARCHAR2(240) PATH './ADJUSTMENT_PERIOD_FLAG',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        context VARCHAR2(240) PATH './CONTEXT',
                        elimination_confirmed_flag VARCHAR2(240) PATH './ELIMINATION_CONFIRMED_FLAG',
                        chronological_seq_status_code VARCHAR2(240) PATH './CHRONOLOGICAL_SEQ_STATUS_CODE',
                        ledger_id NUMBER PATH './LEDGER_ID',
                        migration_status_code VARCHAR2(240) PATH './MIGRATION_STATUS_CODE',
                        track_bc_ytd_flag VARCHAR2(240) PATH './TRACK_BC_YTD_FLAG'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_GL_PERIOD_STATUSES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        gl_period_statuses l
                    WHERE
                            l.application_id = x.application_id
                        AND l.period_name = x.period_name
                        AND l.ledger_id = x.ledger_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_period_statuses_insert_update',
            p_tracker => 'agis_gl_period_statuses_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_gl_period_statuses_insert_update');
    END agis_gl_period_statuses_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_PERIODS_INSERT_UPDATE
	*
	*  Description:  Syncs GL Period Statuses BIP Report into GL_PERIODS table
	*
	**************************************************************************/

    PROCEDURE agis_gl_periods_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            period_set_name        gl_periods.period_set_name%TYPE,
            description            gl_periods.description%TYPE,
            creation_date          gl_periods.creation_date%TYPE,
            created_by             gl_periods.created_by%TYPE,
            last_update_date       gl_periods.last_update_date%TYPE,
            last_updated_by        gl_periods.last_updated_by%TYPE,
            last_update_login      gl_periods.last_update_login%TYPE,
            period_year            gl_periods.period_year%TYPE,
            start_date             gl_periods.start_date%TYPE,
            end_date               gl_periods.end_date%TYPE,
            year_start_date        gl_periods.year_start_date%TYPE,
            quarter_start_date     gl_periods.quarter_start_date%TYPE,
            quarter_num            gl_periods.quarter_num%TYPE,
            period_type            gl_periods.period_type%TYPE,
            period_num             gl_periods.period_num%TYPE,
            period_name            gl_periods.period_name%TYPE,
            adjustment_period_flag gl_periods.adjustment_period_flag%TYPE,
            attribute1             gl_periods.attribute1%TYPE,
            attribute2             gl_periods.attribute2%TYPE,
            attribute3             gl_periods.attribute3%TYPE,
            attribute4             gl_periods.attribute4%TYPE,
            attribute5             gl_periods.attribute5%TYPE,
            context                gl_periods.context%TYPE,
            attribute6             gl_periods.attribute6%TYPE,
            attribute7             gl_periods.attribute7%TYPE,
            attribute8             gl_periods.attribute8%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_period_statuses_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_GL_PERIODS',
        'AGIS_GL_PERIODS');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PERIOD_SET_NAME
				,x.DESCRIPTION
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.PERIOD_YEAR
				,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.YEAR_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.QUARTER_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.QUARTER_NUM
				,x.PERIOD_TYPE
				,x.PERIOD_NUM
				,PERIOD_NAME                        
				,ADJUSTMENT_PERIOD_FLAG              
				,ATTRIBUTE1                           
				,ATTRIBUTE2                           
				,ATTRIBUTE3                           
				,ATTRIBUTE4                           
				,ATTRIBUTE5                           
				,CONTEXT                                         
				,ATTRIBUTE6        
				,ATTRIBUTE7                            
				,ATTRIBUTE8                                  

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PERIOD_SET_NAME VARCHAR2(240) PATH ''./PERIOD_SET_NAME''
										  ,DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,PERIOD_YEAR NUMBER PATH ''./PERIOD_YEAR''
										  ,START_DATE VARCHAR2(240) PATH ''./START_DATE''
										  ,END_DATE VARCHAR2(240) PATH ''./END_DATE''
										  ,YEAR_START_DATE VARCHAR2(240) PATH ''./YEAR_START_DATE''
										  ,QUARTER_START_DATE VARCHAR2(240) PATH ''./QUARTER_START_DATE''
										  ,QUARTER_NUM NUMBER PATH ''./QUARTER_NUM''
										  ,PERIOD_TYPE VARCHAR2(240) PATH ''./PERIOD_TYPE''
										  ,PERIOD_NUM NUMBER PATH ''./PERIOD_NUM''
										  ,PERIOD_NAME VARCHAR2(240) PATH ''./PERIOD_NAME''                        
										  ,ADJUSTMENT_PERIOD_FLAG VARCHAR2(240) PATH ''./ADJUSTMENT_PERIOD_FLAG''              
										  ,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''                           
										  ,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''                           
										  ,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''                           
										  ,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''                           
										  ,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''                           
										  ,CONTEXT VARCHAR2(240) PATH ''./CONTEXT''                                        
										  ,ATTRIBUTE6 VARCHAR2(240) PATH ''./ATTRIBUTE6''        
										  ,ATTRIBUTE7 NUMBER PATH ''./ATTRIBUTE7''                            
										  ,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8''                
										  ) x
				WHERE t.template_name LIKE ''AGIS_GL_PERIODS''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM GL_PERIODS  L WHERE L.PERIOD_SET_NAME = x.PERIOD_SET_NAME
														 AND L.PERIOD_NAME=x.PERIOD_NAME)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE gl_periods
            SET
                period_set_name = agis_lookup_xml_data_rec.period_set_name,
                description = agis_lookup_xml_data_rec.description,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                period_year = agis_lookup_xml_data_rec.period_year,
                start_date = agis_lookup_xml_data_rec.start_date,
                end_date = agis_lookup_xml_data_rec.end_date,
                year_start_date = agis_lookup_xml_data_rec.year_start_date,
                quarter_start_date = agis_lookup_xml_data_rec.quarter_start_date,
                quarter_num = agis_lookup_xml_data_rec.quarter_num,
                period_type = agis_lookup_xml_data_rec.period_type,
                period_num = agis_lookup_xml_data_rec.period_num,
                period_name = agis_lookup_xml_data_rec.period_name,
                adjustment_period_flag = agis_lookup_xml_data_rec.adjustment_period_flag,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                context = agis_lookup_xml_data_rec.context,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8
            WHERE
                    period_set_name = agis_lookup_xml_data_rec.period_set_name
                AND period_name = agis_lookup_xml_data_rec.period_name;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO gl_periods (
            period_set_name,
            description,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            period_year,
            start_date,
            end_date,
            year_start_date,
            quarter_start_date,
            quarter_num,
            period_type,
            period_num,
            period_name,
            adjustment_period_flag,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            context,
            attribute6,
            attribute7,
            attribute8
        )
            ( SELECT
                x.period_set_name,
                x.description,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.period_year,
                to_char(to_date(substr(x.start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.year_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.quarter_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.quarter_num,
                x.period_type,
                x.period_num,
                period_name,
                adjustment_period_flag,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                context,
                attribute6,
                attribute7,
                attribute8
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        period_set_name VARCHAR2(240) PATH './PERIOD_SET_NAME',
                        description VARCHAR2(240) PATH './DESCRIPTION',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        period_year NUMBER PATH './PERIOD_YEAR',
                        start_date VARCHAR2(240) PATH './START_DATE',
                        end_date VARCHAR2(240) PATH './END_DATE',
                        year_start_date VARCHAR2(240) PATH './YEAR_START_DATE',
                        quarter_start_date VARCHAR2(240) PATH './QUARTER_START_DATE',
                        quarter_num NUMBER PATH './QUARTER_NUM',
                        period_type VARCHAR2(240) PATH './PERIOD_TYPE',
                        period_num NUMBER PATH './PERIOD_NUM',
                        period_name VARCHAR2(240) PATH './PERIOD_NAME',
                        adjustment_period_flag VARCHAR2(240) PATH './ADJUSTMENT_PERIOD_FLAG',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        context VARCHAR2(240) PATH './CONTEXT',
                        attribute6 VARCHAR2(240) PATH './ATTRIBUTE6',
                        attribute7 NUMBER PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(240) PATH './ATTRIBUTE8'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_GL_PERIODS'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        gl_periods l
                    WHERE
                            l.period_set_name = x.period_set_name
                        AND l.period_name = x.period_name
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_periods_insert_update', p_tracker =>
            'agis_gl_periods_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_gl_periods_insert_update');
    END agis_gl_periods_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_GL_LEDGERS_INSERT_UPDATE
	*
	*  Description:  Syncs GL Ledgers BIP Report into GL_LEDGERS table
	*
	**************************************************************************/

    PROCEDURE agis_gl_ledgers_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            ledger_id                      gl_ledgers.ledger_id%TYPE,
            description                    gl_ledgers.description%TYPE,
            creation_date                  gl_ledgers.creation_date%TYPE,
            created_by                     gl_ledgers.created_by%TYPE,
            last_update_date               gl_ledgers.last_update_date%TYPE,
            last_updated_by                gl_ledgers.last_updated_by%TYPE,
            last_update_login              gl_ledgers.last_update_login%TYPE,
            name                           gl_ledgers.name%TYPE,
            short_name                     gl_ledgers.short_name%TYPE,
            ledger_category_code           gl_ledgers.ledger_category_code%TYPE,
            alc_ledger_type_code           gl_ledgers.alc_ledger_type_code%TYPE,
            object_type_code               gl_ledgers.object_type_code%TYPE,
            le_ledger_type_code            gl_ledgers.le_ledger_type_code%TYPE,
            completion_status_code         gl_ledgers.completion_status_code%TYPE,
            configuration_id               gl_ledgers.configuration_id%TYPE,
            chart_of_accounts_id           gl_ledgers.chart_of_accounts_id%TYPE,
            currency_code                  gl_ledgers.currency_code%TYPE,
            period_set_name                gl_ledgers.period_set_name%TYPE,
            accounted_period_type          gl_ledgers.accounted_period_type%TYPE,
            first_ledger_period_name       gl_ledgers.first_ledger_period_name%TYPE,
            ret_earn_code_combination_id   gl_ledgers.ret_earn_code_combination_id%TYPE,
            suspense_allowed_flag          gl_ledgers.suspense_allowed_flag%TYPE,
            allow_intercompany_post_flag   gl_ledgers.allow_intercompany_post_flag%TYPE,
            track_rounding_imbalance_flag  gl_ledgers.track_rounding_imbalance_flag%TYPE,
            enable_average_balances_flag   gl_ledgers.enable_average_balances_flag%TYPE,
            cum_trans_code_combination_id  gl_ledgers.cum_trans_code_combination_id%TYPE,
            res_encumb_code_combination_id gl_ledgers.res_encumb_code_combination_id%TYPE,
            net_income_code_combination_id gl_ledgers.net_income_code_combination_id%TYPE,
            rounding_code_combination_id   gl_ledgers.rounding_code_combination_id%TYPE,
            enable_budgetary_control_flag  gl_ledgers.enable_budgetary_control_flag%TYPE,
            require_budget_journals_flag   gl_ledgers.require_budget_journals_flag%TYPE,
            enable_je_approval_flag        gl_ledgers.enable_je_approval_flag%TYPE,
            enable_automatic_tax_flag      gl_ledgers.enable_automatic_tax_flag%TYPE,
            consolidation_ledger_flag      gl_ledgers.consolidation_ledger_flag%TYPE,
            translate_eod_flag             gl_ledgers.translate_eod_flag%TYPE,
            translate_qatd_flag            gl_ledgers.translate_qatd_flag%TYPE,
            translate_yatd_flag            gl_ledgers.translate_yatd_flag%TYPE,
            transaction_calendar_id        gl_ledgers.transaction_calendar_id%TYPE,
            daily_translation_rate_type    gl_ledgers.daily_translation_rate_type%TYPE,
            automatically_created_flag     gl_ledgers.automatically_created_flag%TYPE,
            bal_seg_value_option_code      gl_ledgers.bal_seg_value_option_code%TYPE,
            bal_seg_column_name            gl_ledgers.bal_seg_column_name%TYPE,
            mgt_seg_value_option_code      gl_ledgers.mgt_seg_value_option_code%TYPE,
            mgt_seg_column_name            gl_ledgers.mgt_seg_column_name%TYPE,
            bal_seg_value_set_id           gl_ledgers.bal_seg_value_set_id%TYPE,
            mgt_seg_value_set_id           gl_ledgers.mgt_seg_value_set_id%TYPE,
            implicit_access_set_id         gl_ledgers.implicit_access_set_id%TYPE,
            criteria_set_id                gl_ledgers.criteria_set_id%TYPE,
            future_enterable_periods_limit gl_ledgers.future_enterable_periods_limit%TYPE,
            ledger_attributes              gl_ledgers.ledger_attributes%TYPE,
            implicit_ledger_set_id         gl_ledgers.implicit_ledger_set_id%TYPE,
            latest_opened_period_name      gl_ledgers.latest_opened_period_name%TYPE,
            latest_encumbrance_year        gl_ledgers.latest_encumbrance_year%TYPE,
            period_average_rate_type       gl_ledgers.period_average_rate_type%TYPE,
            period_end_rate_type           gl_ledgers.period_end_rate_type%TYPE,
            budget_period_avg_rate_type    gl_ledgers.budget_period_avg_rate_type%TYPE,
            budget_period_end_rate_type    gl_ledgers.budget_period_end_rate_type%TYPE,
            sla_accounting_method_code     gl_ledgers.sla_accounting_method_code%TYPE,
            sla_accounting_method_type     gl_ledgers.sla_accounting_method_type%TYPE,
            sla_description_language       gl_ledgers.sla_description_language%TYPE,
            sla_entered_cur_bal_sus_ccid   gl_ledgers.sla_entered_cur_bal_sus_ccid%TYPE,
            sla_sequencing_flag            gl_ledgers.sla_sequencing_flag%TYPE,
            sla_bal_by_ledger_curr_flag    gl_ledgers.sla_bal_by_ledger_curr_flag%TYPE,
            sla_ledger_cur_bal_sus_ccid    gl_ledgers.sla_ledger_cur_bal_sus_ccid%TYPE,
            enable_secondary_track_flag    gl_ledgers.enable_secondary_track_flag%TYPE,
            enable_reval_ss_track_flag     gl_ledgers.enable_reval_ss_track_flag%TYPE,
            enable_reconciliation_flag     gl_ledgers.enable_reconciliation_flag%TYPE,
            create_je_flag                 gl_ledgers.create_je_flag%TYPE,
            sla_ledger_cash_basis_flag     gl_ledgers.sla_ledger_cash_basis_flag%TYPE,
            complete_flag                  gl_ledgers.complete_flag%TYPE,
            commitment_budget_flag         gl_ledgers.commitment_budget_flag%TYPE,
            net_closing_bal_flag           gl_ledgers.net_closing_bal_flag%TYPE,
            automate_sec_jrnl_rev_flag     gl_ledgers.automate_sec_jrnl_rev_flag%TYPE,
            attribute1                     gl_ledgers.attribute1%TYPE,
            attribute2                     gl_ledgers.attribute2%TYPE,
            attribute3                     gl_ledgers.attribute3%TYPE,
            attribute4                     gl_ledgers.attribute4%TYPE,
            attribute5                     gl_ledgers.attribute5%TYPE,
            context                        gl_ledgers.context%TYPE,
            attribute6                     gl_ledgers.attribute6%TYPE,
            attribute7                     gl_ledgers.attribute7%TYPE,
            attribute8                     gl_ledgers.attribute8%TYPE,
            attribute9                     gl_ledgers.attribute9%TYPE,
            attribute10                    gl_ledgers.attribute10%TYPE,
            attribute11                    gl_ledgers.attribute11%TYPE,
            attribute12                    gl_ledgers.attribute12%TYPE,
            attribute13                    gl_ledgers.attribute13%TYPE,
            attribute14                    gl_ledgers.attribute14%TYPE,
            attribute15                    gl_ledgers.attribute15%TYPE,
            attribute_category             gl_ledgers.attribute_category%TYPE,
            attribute_number1              gl_ledgers.attribute_number1%TYPE,
            attribute_number2              gl_ledgers.attribute_number2%TYPE,
            attribute_number3              gl_ledgers.attribute_number3%TYPE,
            attribute_number4              gl_ledgers.attribute_number4%TYPE,
            attribute_number5              gl_ledgers.attribute_number5%TYPE,
            attribute_date1                gl_ledgers.attribute_date1%TYPE,
            attribute_date2                gl_ledgers.attribute_date2%TYPE,
            attribute_date3                gl_ledgers.attribute_date3%TYPE,
            attribute_date4                gl_ledgers.attribute_date4%TYPE,
            attribute_date5                gl_ledgers.attribute_date5%TYPE,
            object_version_number          gl_ledgers.object_version_number%TYPE,
            ussgl_option_code              gl_ledgers.ussgl_option_code%TYPE,
            validate_journal_ref_date      gl_ledgers.validate_journal_ref_date%TYPE,
            jrnls_group_by_date_flag       gl_ledgers.jrnls_group_by_date_flag%TYPE,
            reval_from_pri_lgr_curr        gl_ledgers.reval_from_pri_lgr_curr%TYPE,
            autorev_after_open_prd_flag    gl_ledgers.autorev_after_open_prd_flag%TYPE,
            prior_prd_notification_flag    gl_ledgers.prior_prd_notification_flag%TYPE,
            pop_up_stat_account_flag       gl_ledgers.pop_up_stat_account_flag%TYPE,
            threshold_amount               gl_ledgers.threshold_amount%TYPE,
            number_of_processors           gl_ledgers.number_of_processors%TYPE,
            processing_unit_size           gl_ledgers.processing_unit_size%TYPE,
            release_upgrade_from           gl_ledgers.release_upgrade_from%TYPE,
            cross_lgr_clr_acc_ccid         gl_ledgers.cross_lgr_clr_acc_ccid%TYPE,
            interco_gain_loss_ccid         gl_ledgers.interco_gain_loss_ccid%TYPE,
            sequencing_mode_code           gl_ledgers.sequencing_mode_code%TYPE,
            doc_sequencing_option_code     gl_ledgers.doc_sequencing_option_code%TYPE,
            enf_seq_date_correlation_code  gl_ledgers.enf_seq_date_correlation_code%TYPE,
            ar_doc_sequencing_option_flag  gl_ledgers.ar_doc_sequencing_option_flag%TYPE,
            ap_doc_sequencing_option_flag  gl_ledgers.ap_doc_sequencing_option_flag%TYPE,
            minimum_threshold_amount       gl_ledgers.minimum_threshold_amount%TYPE,
            strict_period_close_flag       gl_ledgers.strict_period_close_flag%TYPE,
            income_stmt_adb_status_code    gl_ledgers.income_stmt_adb_status_code%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_gl_ledgers_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_GL_LEDGER',
        'AGIS_GL_LEDGER');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.LEDGER_ID
				,x.DESCRIPTION
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.NAME
				,x.SHORT_NAME
				,x.LEDGER_CATEGORY_CODE
				,x.ALC_LEDGER_TYPE_CODE
				,x.OBJECT_TYPE_CODE
				,x.LE_LEDGER_TYPE_CODE
				,x.COMPLETION_STATUS_CODE
				,x.CONFIGURATION_ID
				,CHART_OF_ACCOUNTS_ID                        
				,CURRENCY_CODE   
				,PERIOD_SET_NAME 
				,ACCOUNTED_PERIOD_TYPE 
				,FIRST_LEDGER_PERIOD_NAME 
				,RET_EARN_CODE_COMBINATION_ID
				,SUSPENSE_ALLOWED_FLAG 
				,ALLOW_INTERCOMPANY_POST_FLAG 
				,TRACK_ROUNDING_IMBALANCE_FLAG 
				,ENABLE_AVERAGE_BALANCES_FLAG 
				,CUM_TRANS_CODE_COMBINATION_ID
				,RES_ENCUMB_CODE_COMBINATION_ID 
				,NET_INCOME_CODE_COMBINATION_ID 
				,ROUNDING_CODE_COMBINATION_ID 
				,ENABLE_BUDGETARY_CONTROL_FLAG 
				,REQUIRE_BUDGET_JOURNALS_FLAG 
				,ENABLE_JE_APPROVAL_FLAG 
				,ENABLE_AUTOMATIC_TAX_FLAG 
				,CONSOLIDATION_LEDGER_FLAG 
				,TRANSLATE_EOD_FLAG 
				,TRANSLATE_QATD_FLAG 
				,TRANSLATE_YATD_FLAG 
				,TRANSACTION_CALENDAR_ID 
				,DAILY_TRANSLATION_RATE_TYPE 
				,AUTOMATICALLY_CREATED_FLAG 
				,BAL_SEG_VALUE_OPTION_CODE 
				,BAL_SEG_COLUMN_NAME 
				,MGT_SEG_VALUE_OPTION_CODE 
				,MGT_SEG_COLUMN_NAME 
				,BAL_SEG_VALUE_SET_ID 
				,MGT_SEG_VALUE_SET_ID 
				,IMPLICIT_ACCESS_SET_ID 
				,CRITERIA_SET_ID 
				,FUTURE_ENTERABLE_PERIODS_LIMIT
				,LEDGER_ATTRIBUTES 
				,IMPLICIT_LEDGER_SET_ID 
				,LATEST_OPENED_PERIOD_NAME 
				,LATEST_ENCUMBRANCE_YEAR 
				,PERIOD_AVERAGE_RATE_TYPE 
				,PERIOD_END_RATE_TYPE 
				,BUDGET_PERIOD_AVG_RATE_TYPE 
				,BUDGET_PERIOD_END_RATE_TYPE 
				,SLA_ACCOUNTING_METHOD_CODE 
				,SLA_ACCOUNTING_METHOD_TYPE 
				,SLA_DESCRIPTION_LANGUAGE 
				,SLA_ENTERED_CUR_BAL_SUS_CCID 
				,SLA_SEQUENCING_FLAG 
				,SLA_BAL_BY_LEDGER_CURR_FLAG 
				,SLA_LEDGER_CUR_BAL_SUS_CCID 
				,ENABLE_SECONDARY_TRACK_FLAG 
				,ENABLE_REVAL_SS_TRACK_FLAG 
				,ENABLE_RECONCILIATION_FLAG
				,CREATE_JE_FLAG
				,SLA_LEDGER_CASH_BASIS_FLAG
				,COMPLETE_FLAG
				,COMMITMENT_BUDGET_FLAG
				,NET_CLOSING_BAL_FLAG
				,AUTOMATE_SEC_JRNL_REV_FLAG
				,ATTRIBUTE1                           
				,ATTRIBUTE2                           
				,ATTRIBUTE3                           
				,ATTRIBUTE4                           
				,ATTRIBUTE5                           
				,CONTEXT                                     
				,ATTRIBUTE6        
				,ATTRIBUTE7                            
				,ATTRIBUTE8 
				,ATTRIBUTE9                           
				,ATTRIBUTE10                          
				,ATTRIBUTE11                          
				,ATTRIBUTE12                          
				,ATTRIBUTE13                          
				,ATTRIBUTE14                         
				,ATTRIBUTE15                         	
				,ATTRIBUTE_CATEGORY
				,ATTRIBUTE_NUMBER1
				,ATTRIBUTE_NUMBER2 
				,ATTRIBUTE_NUMBER3
				,ATTRIBUTE_NUMBER4
				,ATTRIBUTE_NUMBER5
				,TO_CHAR(TO_DATE(SUBSTR(x.ATTRIBUTE_DATE1, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.ATTRIBUTE_DATE2, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.ATTRIBUTE_DATE3, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.ATTRIBUTE_DATE4, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.ATTRIBUTE_DATE5, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,OBJECT_VERSION_NUMBER
				,USSGL_OPTION_CODE  
				,VALIDATE_JOURNAL_REF_DATE
				,JRNLS_GROUP_BY_DATE_FLAG
				,REVAL_FROM_PRI_LGR_CURR
				,AUTOREV_AFTER_OPEN_PRD_FLAG
				,PRIOR_PRD_NOTIFICATION_FLAG
				,POP_UP_STAT_ACCOUNT_FLAG
				,THRESHOLD_AMOUNT
				,NUMBER_OF_PROCESSORS
				,PROCESSING_UNIT_SIZE
				,RELEASE_UPGRADE_FROM
				,CROSS_LGR_CLR_ACC_CCID
				,INTERCO_GAIN_LOSS_CCID
				,SEQUENCING_MODE_CODE
				,DOC_SEQUENCING_OPTION_CODE
				,ENF_SEQ_DATE_CORRELATION_CODE
				,AR_DOC_SEQUENCING_OPTION_FLAG
				,AP_DOC_SEQUENCING_OPTION_FLAG
				,MINIMUM_THRESHOLD_AMOUNT
				,STRICT_PERIOD_CLOSE_FLAG
				,INCOME_STMT_ADB_STATUS_CODE
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										LEDGER_ID NUMBER PATH ''./LEDGER_ID''
										,DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION''
										,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										,NAME VARCHAR2(240) PATH ''./NAME''
										,SHORT_NAME VARCHAR2(240) PATH ''./SHORT_NAME''
										,LEDGER_CATEGORY_CODE VARCHAR2(240) PATH ''./LEDGER_CATEGORY_CODE''
										,ALC_LEDGER_TYPE_CODE VARCHAR2(240) PATH ''./ALC_LEDGER_TYPE_CODE''
										,OBJECT_TYPE_CODE VARCHAR2(240) PATH ''./OBJECT_TYPE_CODE''
										,LE_LEDGER_TYPE_CODE VARCHAR2(240) PATH ''./LE_LEDGER_TYPE_CODE''
										,COMPLETION_STATUS_CODE VARCHAR2(240) PATH ''./COMPLETION_STATUS_CODE''
										,CONFIGURATION_ID NUMBER PATH ''./CONFIGURATION_ID''
										,CHART_OF_ACCOUNTS_ID NUMBER PATH ''./CHART_OF_ACCOUNTS_ID''                        
										,CURRENCY_CODE VARCHAR2(240) PATH ''./CURRENCY_CODE'' 
										,PERIOD_SET_NAME VARCHAR2(240) PATH ''./PERIOD_SET_NAME'' 
										,ACCOUNTED_PERIOD_TYPE VARCHAR2(240) PATH ''./ACCOUNTED_PERIOD_TYPE'' 
										,FIRST_LEDGER_PERIOD_NAME VARCHAR2(240) PATH ''./FIRST_LEDGER_PERIOD_NAME'' 
										,RET_EARN_CODE_COMBINATION_ID NUMBER PATH ''./RET_EARN_CODE_COMBINATION_ID'' 
										,SUSPENSE_ALLOWED_FLAG VARCHAR2(240) PATH ''./SUSPENSE_ALLOWED_FLAG'' 
										,ALLOW_INTERCOMPANY_POST_FLAG VARCHAR2(240) PATH ''./ALLOW_INTERCOMPANY_POST_FLAG'' 
										,TRACK_ROUNDING_IMBALANCE_FLAG VARCHAR2(240) PATH ''./TRACK_ROUNDING_IMBALANCE_FLAG'' 
										,ENABLE_AVERAGE_BALANCES_FLAG VARCHAR2(240) PATH ''./ENABLE_AVERAGE_BALANCES_FLAG'' 
										,CUM_TRANS_CODE_COMBINATION_ID NUMBER PATH ''./CUM_TRANS_CODE_COMBINATION_ID'' 
										,RES_ENCUMB_CODE_COMBINATION_ID NUMBER PATH ''./RES_ENCUMB_CODE_COMBINATION_ID'' 
										,NET_INCOME_CODE_COMBINATION_ID NUMBER PATH ''./NET_INCOME_CODE_COMBINATION_ID'' 
										,ROUNDING_CODE_COMBINATION_ID NUMBER PATH ''./ROUNDING_CODE_COMBINATION_ID'' 
										,ENABLE_BUDGETARY_CONTROL_FLAG VARCHAR2(240) PATH ''./ENABLE_BUDGETARY_CONTROL_FLAG'' 
										,REQUIRE_BUDGET_JOURNALS_FLAG VARCHAR2(240) PATH ''./REQUIRE_BUDGET_JOURNALS_FLAG'' 
										,ENABLE_JE_APPROVAL_FLAG VARCHAR2(240) PATH ''./ENABLE_JE_APPROVAL_FLAG'' 
										,ENABLE_AUTOMATIC_TAX_FLAG VARCHAR2(240) PATH ''./ENABLE_AUTOMATIC_TAX_FLAG'' 
										,CONSOLIDATION_LEDGER_FLAG VARCHAR2(240) PATH ''./CONSOLIDATION_LEDGER_FLAG'' 
										,TRANSLATE_EOD_FLAG VARCHAR2(240) PATH ''./TRANSLATE_EOD_FLAG'' 
										,TRANSLATE_QATD_FLAG VARCHAR2(240) PATH ''./TRANSLATE_QATD_FLAG'' 
										,TRANSLATE_YATD_FLAG VARCHAR2(240) PATH ''./TRANSLATE_YATD_FLAG'' 
										,TRANSACTION_CALENDAR_ID NUMBER PATH ''./TRANSACTION_CALENDAR_ID'' 
										,DAILY_TRANSLATION_RATE_TYPE VARCHAR2(240) PATH ''./DAILY_TRANSLATION_RATE_TYPE'' 
										,AUTOMATICALLY_CREATED_FLAG VARCHAR2(240) PATH ''./AUTOMATICALLY_CREATED_FLAG'' 
										,BAL_SEG_VALUE_OPTION_CODE VARCHAR2(240) PATH ''./BAL_SEG_VALUE_OPTION_CODE'' 
										,BAL_SEG_COLUMN_NAME VARCHAR2(240) PATH ''./BAL_SEG_COLUMN_NAME'' 
										,MGT_SEG_VALUE_OPTION_CODE VARCHAR2(240) PATH ''./MGT_SEG_VALUE_OPTION_CODE'' 
										,MGT_SEG_COLUMN_NAME VARCHAR2(240) PATH ''./MGT_SEG_COLUMN_NAME'' 
										,BAL_SEG_VALUE_SET_ID NUMBER PATH ''./BAL_SEG_VALUE_SET_ID'' 
										,MGT_SEG_VALUE_SET_ID NUMBER PATH ''./MGT_SEG_VALUE_SET_ID'' 
										,IMPLICIT_ACCESS_SET_ID NUMBER PATH ''./IMPLICIT_ACCESS_SET_ID'' 
										,CRITERIA_SET_ID NUMBER PATH ''./CRITERIA_SET_ID'' 
										,FUTURE_ENTERABLE_PERIODS_LIMIT NUMBER PATH ''./FUTURE_ENTERABLE_PERIODS_LIMIT'' 
										,LEDGER_ATTRIBUTES VARCHAR2(2000) PATH ''./LEDGER_ATTRIBUTES'' 
										,IMPLICIT_LEDGER_SET_ID NUMBER PATH ''./IMPLICIT_LEDGER_SET_ID'' 
										,LATEST_OPENED_PERIOD_NAME VARCHAR2(240) PATH ''./LATEST_OPENED_PERIOD_NAME'' 
										,LATEST_ENCUMBRANCE_YEAR NUMBER PATH ''./LATEST_ENCUMBRANCE_YEAR'' 
										,PERIOD_AVERAGE_RATE_TYPE VARCHAR2(240) PATH ''./PERIOD_AVERAGE_RATE_TYPE'' 
										,PERIOD_END_RATE_TYPE VARCHAR2(240) PATH ''./PERIOD_END_RATE_TYPE'' 
										,BUDGET_PERIOD_AVG_RATE_TYPE VARCHAR2(240) PATH ''./BUDGET_PERIOD_AVG_RATE_TYPE'' 
										,BUDGET_PERIOD_END_RATE_TYPE VARCHAR2(240) PATH ''./BUDGET_PERIOD_END_RATE_TYPE'' 
										,SLA_ACCOUNTING_METHOD_CODE VARCHAR2(240) PATH ''./SLA_ACCOUNTING_METHOD_CODE'' 
										,SLA_ACCOUNTING_METHOD_TYPE VARCHAR2(240) PATH ''./SLA_ACCOUNTING_METHOD_TYPE'' 
										,SLA_DESCRIPTION_LANGUAGE VARCHAR2(240) PATH ''./SLA_DESCRIPTION_LANGUAGE'' 
										,SLA_ENTERED_CUR_BAL_SUS_CCID NUMBER PATH ''./SLA_ENTERED_CUR_BAL_SUS_CCID'' 
										,SLA_SEQUENCING_FLAG VARCHAR2(240) PATH ''./SLA_SEQUENCING_FLAG'' 
										,SLA_BAL_BY_LEDGER_CURR_FLAG VARCHAR2(240) PATH ''./SLA_BAL_BY_LEDGER_CURR_FLAG'' 
										,SLA_LEDGER_CUR_BAL_SUS_CCID VARCHAR2(240) PATH ''./SLA_LEDGER_CUR_BAL_SUS_CCID'' 
										,ENABLE_SECONDARY_TRACK_FLAG VARCHAR2(240) PATH ''./ENABLE_SECONDARY_TRACK_FLAG'' 
										,ENABLE_REVAL_SS_TRACK_FLAG VARCHAR2(240) PATH ''./ENABLE_REVAL_SS_TRACK_FLAG'' 
										,ENABLE_RECONCILIATION_FLAG VARCHAR2(240) PATH ''./ENABLE_RECONCILIATION_FLAG'' 
										,CREATE_JE_FLAG VARCHAR2(240) PATH ''./CREATE_JE_FLAG'' 
										,SLA_LEDGER_CASH_BASIS_FLAG VARCHAR2(240) PATH ''./SLA_LEDGER_CASH_BASIS_FLAG'' 
										,COMPLETE_FLAG VARCHAR2(240) PATH ''./COMPLETE_FLAG'' 
										,COMMITMENT_BUDGET_FLAG VARCHAR2(240) PATH ''./COMMITMENT_BUDGET_FLAG'' 
										,NET_CLOSING_BAL_FLAG VARCHAR2(240) PATH ''./NET_CLOSING_BAL_FLAG'' 
										,AUTOMATE_SEC_JRNL_REV_FLAG VARCHAR2(240) PATH ''./AUTOMATE_SEC_JRNL_REV_FLAG'' 
										,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''                           
										,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''                           
										,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''                           
										,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''                           
										,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''                           
										,CONTEXT VARCHAR2(240) PATH ''./CONTEXT''                                     
										,ATTRIBUTE6 VARCHAR2(240) PATH ''./ATTRIBUTE6''        
										,ATTRIBUTE7 VARCHAR2(240) PATH ''./ATTRIBUTE7''                            
										,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8''
										,ATTRIBUTE9 VARCHAR2(240) PATH ''./ATTRIBUTE9''
										,ATTRIBUTE10 VARCHAR2(240) PATH ''./ATTRIBUTE10''                          
										,ATTRIBUTE11 VARCHAR2(240) PATH ''./ATTRIBUTE11''                         
										,ATTRIBUTE12 VARCHAR2(240) PATH ''./ATTRIBUTE12''                         
										,ATTRIBUTE13 VARCHAR2(240) PATH ''./ATTRIBUTE13''                         
										,ATTRIBUTE14 VARCHAR2(240) PATH ''./ATTRIBUTE14''                        
										,ATTRIBUTE15 VARCHAR2(240) PATH ''./ATTRIBUTE15''
										,ATTRIBUTE_CATEGORY VARCHAR2(240) PATH ''./ATTRIBUTE_CATEGORY''
										,ATTRIBUTE_NUMBER1 NUMBER PATH ''./ATTRIBUTE_NUMBER1''
										,ATTRIBUTE_NUMBER2 NUMBER PATH ''./ATTRIBUTE_NUMBER2''
										,ATTRIBUTE_NUMBER3 NUMBER PATH ''./ATTRIBUTE_NUMBER3''
										,ATTRIBUTE_NUMBER4 NUMBER PATH ''./ATTRIBUTE_NUMBER4''
										,ATTRIBUTE_NUMBER5 NUMBER PATH ''./ATTRIBUTE_NUMBER5''
										,ATTRIBUTE_DATE1 VARCHAR2(240) PATH ''./ATTRIBUTE_DATE1''
										,ATTRIBUTE_DATE2 VARCHAR2(240) PATH ''./ATTRIBUTE_DATE2''
										,ATTRIBUTE_DATE3 VARCHAR2(240) PATH ''./ATTRIBUTE_DATE3''
										,ATTRIBUTE_DATE4 VARCHAR2(240) PATH ''./ATTRIBUTE_DATE4''
										,ATTRIBUTE_DATE5 VARCHAR2(240) PATH ''./ATTRIBUTE_DATE5''
										,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER''
										,USSGL_OPTION_CODE VARCHAR2(240) PATH ''./USSGL_OPTION_CODE''  
										,VALIDATE_JOURNAL_REF_DATE VARCHAR2(240) PATH ''./VALIDATE_JOURNAL_REF_DATE''
										,JRNLS_GROUP_BY_DATE_FLAG VARCHAR2(240) PATH ''./JRNLS_GROUP_BY_DATE_FLAG''
										,REVAL_FROM_PRI_LGR_CURR VARCHAR2(240) PATH ''./REVAL_FROM_PRI_LGR_CURR''
										,AUTOREV_AFTER_OPEN_PRD_FLAG VARCHAR2(240) PATH ''./AUTOREV_AFTER_OPEN_PRD_FLAG''
										,PRIOR_PRD_NOTIFICATION_FLAG VARCHAR2(240) PATH ''./PRIOR_PRD_NOTIFICATION_FLAG''
										,POP_UP_STAT_ACCOUNT_FLAG VARCHAR2(240) PATH ''./POP_UP_STAT_ACCOUNT_FLAG''
										,THRESHOLD_AMOUNT NUMBER PATH ''./THRESHOLD_AMOUNT''
										,NUMBER_OF_PROCESSORS NUMBER PATH ''./NUMBER_OF_PROCESSORS''
										,PROCESSING_UNIT_SIZE NUMBER PATH ''./PROCESSING_UNIT_SIZE''
										,RELEASE_UPGRADE_FROM VARCHAR2(240) PATH ''./RELEASE_UPGRADE_FROM''
										,CROSS_LGR_CLR_ACC_CCID NUMBER PATH ''./CROSS_LGR_CLR_ACC_CCID''
										,INTERCO_GAIN_LOSS_CCID NUMBER PATH ''./INTERCO_GAIN_LOSS_CCID''
										,SEQUENCING_MODE_CODE VARCHAR2(240) PATH ''./SEQUENCING_MODE_CODE''
										,DOC_SEQUENCING_OPTION_CODE VARCHAR2(240) PATH ''./DOC_SEQUENCING_OPTION_CODE''
										,ENF_SEQ_DATE_CORRELATION_CODE VARCHAR2(240) PATH ''./ENF_SEQ_DATE_CORRELATION_CODE''
										,AR_DOC_SEQUENCING_OPTION_FLAG VARCHAR2(240) PATH ''./AR_DOC_SEQUENCING_OPTION_FLAG''
										,AP_DOC_SEQUENCING_OPTION_FLAG VARCHAR2(240) PATH ''./AP_DOC_SEQUENCING_OPTION_FLAG''
										,MINIMUM_THRESHOLD_AMOUNT NUMBER PATH ''./MINIMUM_THRESHOLD_AMOUNT''
										,STRICT_PERIOD_CLOSE_FLAG VARCHAR2(240) PATH ''./STRICT_PERIOD_CLOSE_FLAG''
										,INCOME_STMT_ADB_STATUS_CODE VARCHAR2(240) PATH ''./INCOME_STMT_ADB_STATUS_CODE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_GL_LEDGER''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM GL_LEDGERS  L WHERE L.LEDGER_ID = x.LEDGER_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE gl_ledgers
            SET
                ledger_id = agis_lookup_xml_data_rec.ledger_id,
                description = agis_lookup_xml_data_rec.description,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                name = agis_lookup_xml_data_rec.name,
                short_name = agis_lookup_xml_data_rec.short_name,
                ledger_category_code = agis_lookup_xml_data_rec.ledger_category_code,
                alc_ledger_type_code = agis_lookup_xml_data_rec.alc_ledger_type_code,
                object_type_code = agis_lookup_xml_data_rec.object_type_code,
                le_ledger_type_code = agis_lookup_xml_data_rec.le_ledger_type_code,
                completion_status_code = agis_lookup_xml_data_rec.completion_status_code,
                configuration_id = agis_lookup_xml_data_rec.configuration_id,
                chart_of_accounts_id = agis_lookup_xml_data_rec.chart_of_accounts_id,
                currency_code = agis_lookup_xml_data_rec.currency_code,
                period_set_name = agis_lookup_xml_data_rec.period_set_name,
                accounted_period_type = agis_lookup_xml_data_rec.accounted_period_type,
                first_ledger_period_name = agis_lookup_xml_data_rec.first_ledger_period_name,
                ret_earn_code_combination_id = agis_lookup_xml_data_rec.ret_earn_code_combination_id,
                suspense_allowed_flag = agis_lookup_xml_data_rec.suspense_allowed_flag,
                allow_intercompany_post_flag = agis_lookup_xml_data_rec.allow_intercompany_post_flag,
                track_rounding_imbalance_flag = agis_lookup_xml_data_rec.track_rounding_imbalance_flag,
                enable_average_balances_flag = agis_lookup_xml_data_rec.enable_average_balances_flag,
                cum_trans_code_combination_id = agis_lookup_xml_data_rec.cum_trans_code_combination_id,
                res_encumb_code_combination_id = agis_lookup_xml_data_rec.res_encumb_code_combination_id,
                net_income_code_combination_id = agis_lookup_xml_data_rec.net_income_code_combination_id,
                rounding_code_combination_id = agis_lookup_xml_data_rec.rounding_code_combination_id,
                enable_budgetary_control_flag = agis_lookup_xml_data_rec.enable_budgetary_control_flag,
                require_budget_journals_flag = agis_lookup_xml_data_rec.require_budget_journals_flag,
                enable_je_approval_flag = agis_lookup_xml_data_rec.enable_je_approval_flag,
                enable_automatic_tax_flag = agis_lookup_xml_data_rec.enable_automatic_tax_flag,
                consolidation_ledger_flag = agis_lookup_xml_data_rec.consolidation_ledger_flag,
                translate_eod_flag = agis_lookup_xml_data_rec.translate_eod_flag,
                translate_qatd_flag = agis_lookup_xml_data_rec.translate_qatd_flag,
                translate_yatd_flag = agis_lookup_xml_data_rec.translate_yatd_flag,
                transaction_calendar_id = agis_lookup_xml_data_rec.transaction_calendar_id,
                daily_translation_rate_type = agis_lookup_xml_data_rec.daily_translation_rate_type,
                automatically_created_flag = agis_lookup_xml_data_rec.automatically_created_flag,
                bal_seg_value_option_code = agis_lookup_xml_data_rec.bal_seg_value_option_code,
                bal_seg_column_name = agis_lookup_xml_data_rec.bal_seg_column_name,
                mgt_seg_value_option_code = agis_lookup_xml_data_rec.mgt_seg_value_option_code,
                mgt_seg_column_name = agis_lookup_xml_data_rec.mgt_seg_column_name,
                bal_seg_value_set_id = agis_lookup_xml_data_rec.bal_seg_value_set_id,
                mgt_seg_value_set_id = agis_lookup_xml_data_rec.mgt_seg_value_set_id,
                implicit_access_set_id = agis_lookup_xml_data_rec.implicit_access_set_id,
                criteria_set_id = agis_lookup_xml_data_rec.criteria_set_id,
                future_enterable_periods_limit = agis_lookup_xml_data_rec.future_enterable_periods_limit,
                ledger_attributes = agis_lookup_xml_data_rec.ledger_attributes,
                implicit_ledger_set_id = agis_lookup_xml_data_rec.implicit_ledger_set_id,
                latest_opened_period_name = agis_lookup_xml_data_rec.latest_opened_period_name,
                latest_encumbrance_year = agis_lookup_xml_data_rec.latest_encumbrance_year,
                period_average_rate_type = agis_lookup_xml_data_rec.period_average_rate_type,
                period_end_rate_type = agis_lookup_xml_data_rec.period_end_rate_type,
                budget_period_avg_rate_type = agis_lookup_xml_data_rec.budget_period_avg_rate_type,
                budget_period_end_rate_type = agis_lookup_xml_data_rec.budget_period_end_rate_type,
                sla_accounting_method_code = agis_lookup_xml_data_rec.sla_accounting_method_code,
                sla_accounting_method_type = agis_lookup_xml_data_rec.sla_accounting_method_type,
                sla_description_language = agis_lookup_xml_data_rec.sla_description_language,
                sla_entered_cur_bal_sus_ccid = agis_lookup_xml_data_rec.sla_entered_cur_bal_sus_ccid,
                sla_sequencing_flag = agis_lookup_xml_data_rec.sla_sequencing_flag,
                sla_bal_by_ledger_curr_flag = agis_lookup_xml_data_rec.sla_bal_by_ledger_curr_flag,
                sla_ledger_cur_bal_sus_ccid = agis_lookup_xml_data_rec.sla_ledger_cur_bal_sus_ccid,
                enable_secondary_track_flag = agis_lookup_xml_data_rec.enable_secondary_track_flag,
                enable_reval_ss_track_flag = agis_lookup_xml_data_rec.enable_reval_ss_track_flag,
                enable_reconciliation_flag = agis_lookup_xml_data_rec.enable_reconciliation_flag,
                create_je_flag = agis_lookup_xml_data_rec.create_je_flag,
                sla_ledger_cash_basis_flag = agis_lookup_xml_data_rec.sla_ledger_cash_basis_flag,
                complete_flag = agis_lookup_xml_data_rec.complete_flag,
                commitment_budget_flag = agis_lookup_xml_data_rec.commitment_budget_flag,
                net_closing_bal_flag = agis_lookup_xml_data_rec.net_closing_bal_flag,
                automate_sec_jrnl_rev_flag = agis_lookup_xml_data_rec.automate_sec_jrnl_rev_flag,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                context = agis_lookup_xml_data_rec.context,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                attribute_category = agis_lookup_xml_data_rec.attribute_category,
                attribute_number1 = agis_lookup_xml_data_rec.attribute_number1,
                attribute_number2 = agis_lookup_xml_data_rec.attribute_number2,
                attribute_number3 = agis_lookup_xml_data_rec.attribute_number3,
                attribute_number4 = agis_lookup_xml_data_rec.attribute_number4,
                attribute_number5 = agis_lookup_xml_data_rec.attribute_number5,
                attribute_date1 = agis_lookup_xml_data_rec.attribute_date1,
                attribute_date2 = agis_lookup_xml_data_rec.attribute_date2,
                attribute_date3 = agis_lookup_xml_data_rec.attribute_date3,
                attribute_date4 = agis_lookup_xml_data_rec.attribute_date4,
                attribute_date5 = agis_lookup_xml_data_rec.attribute_date5,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                ussgl_option_code = agis_lookup_xml_data_rec.ussgl_option_code,
                validate_journal_ref_date = agis_lookup_xml_data_rec.validate_journal_ref_date,
                jrnls_group_by_date_flag = agis_lookup_xml_data_rec.jrnls_group_by_date_flag,
                reval_from_pri_lgr_curr = agis_lookup_xml_data_rec.reval_from_pri_lgr_curr,
                autorev_after_open_prd_flag = agis_lookup_xml_data_rec.autorev_after_open_prd_flag,
                prior_prd_notification_flag = agis_lookup_xml_data_rec.prior_prd_notification_flag,
                pop_up_stat_account_flag = agis_lookup_xml_data_rec.pop_up_stat_account_flag,
                threshold_amount = agis_lookup_xml_data_rec.threshold_amount,
                number_of_processors = agis_lookup_xml_data_rec.number_of_processors,
                processing_unit_size = agis_lookup_xml_data_rec.processing_unit_size,
                release_upgrade_from = agis_lookup_xml_data_rec.release_upgrade_from,
                cross_lgr_clr_acc_ccid = agis_lookup_xml_data_rec.cross_lgr_clr_acc_ccid,
                interco_gain_loss_ccid = agis_lookup_xml_data_rec.sequencing_mode_code,
                sequencing_mode_code = agis_lookup_xml_data_rec.sequencing_mode_code,
                doc_sequencing_option_code = agis_lookup_xml_data_rec.doc_sequencing_option_code,
                enf_seq_date_correlation_code = agis_lookup_xml_data_rec.enf_seq_date_correlation_code,
                ar_doc_sequencing_option_flag = agis_lookup_xml_data_rec.ar_doc_sequencing_option_flag,
                ap_doc_sequencing_option_flag = agis_lookup_xml_data_rec.ap_doc_sequencing_option_flag,
                minimum_threshold_amount = agis_lookup_xml_data_rec.minimum_threshold_amount,
                strict_period_close_flag = agis_lookup_xml_data_rec.strict_period_close_flag,
                income_stmt_adb_status_code = agis_lookup_xml_data_rec.income_stmt_adb_status_code
            WHERE
                ledger_id = agis_lookup_xml_data_rec.ledger_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO gl_ledgers (
            ledger_id,
            description,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            name,
            short_name,
            ledger_category_code,
            alc_ledger_type_code,
            object_type_code,
            le_ledger_type_code,
            completion_status_code,
            configuration_id,
            chart_of_accounts_id,
            currency_code,
            period_set_name,
            accounted_period_type,
            first_ledger_period_name,
            ret_earn_code_combination_id,
            suspense_allowed_flag,
            allow_intercompany_post_flag,
            track_rounding_imbalance_flag,
            enable_average_balances_flag,
            cum_trans_code_combination_id,
            res_encumb_code_combination_id,
            net_income_code_combination_id,
            rounding_code_combination_id,
            enable_budgetary_control_flag,
            require_budget_journals_flag,
            enable_je_approval_flag,
            enable_automatic_tax_flag,
            consolidation_ledger_flag,
            translate_eod_flag,
            translate_qatd_flag,
            translate_yatd_flag,
            transaction_calendar_id,
            daily_translation_rate_type,
            automatically_created_flag,
            bal_seg_value_option_code,
            bal_seg_column_name,
            mgt_seg_value_option_code,
            mgt_seg_column_name,
            bal_seg_value_set_id,
            mgt_seg_value_set_id,
            implicit_access_set_id,
            criteria_set_id,
            future_enterable_periods_limit,
            ledger_attributes,
            implicit_ledger_set_id,
            latest_opened_period_name,
            latest_encumbrance_year,
            period_average_rate_type,
            period_end_rate_type,
            budget_period_avg_rate_type,
            budget_period_end_rate_type,
            sla_accounting_method_code,
            sla_accounting_method_type,
            sla_description_language,
            sla_entered_cur_bal_sus_ccid,
            sla_sequencing_flag,
            sla_bal_by_ledger_curr_flag,
            sla_ledger_cur_bal_sus_ccid,
            enable_secondary_track_flag,
            enable_reval_ss_track_flag,
            enable_reconciliation_flag,
            create_je_flag,
            sla_ledger_cash_basis_flag,
            complete_flag,
            commitment_budget_flag,
            net_closing_bal_flag,
            automate_sec_jrnl_rev_flag,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            context,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            attribute_category,
            attribute_number1,
            attribute_number2,
            attribute_number3,
            attribute_number4,
            attribute_number5,
            attribute_date1,
            attribute_date2,
            attribute_date3,
            attribute_date4,
            attribute_date5,
            object_version_number,
            ussgl_option_code,
            validate_journal_ref_date,
            jrnls_group_by_date_flag,
            reval_from_pri_lgr_curr,
            autorev_after_open_prd_flag,
            prior_prd_notification_flag,
            pop_up_stat_account_flag,
            threshold_amount,
            number_of_processors,
            processing_unit_size,
            release_upgrade_from,
            cross_lgr_clr_acc_ccid,
            interco_gain_loss_ccid,
            sequencing_mode_code,
            doc_sequencing_option_code,
            enf_seq_date_correlation_code,
            ar_doc_sequencing_option_flag,
            ap_doc_sequencing_option_flag,
            minimum_threshold_amount,
            strict_period_close_flag,
            income_stmt_adb_status_code
        )
            ( SELECT
                x.ledger_id,
                x.description,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.name,
                x.short_name,
                x.ledger_category_code,
                x.alc_ledger_type_code,
                x.object_type_code,
                x.le_ledger_type_code,
                x.completion_status_code,
                x.configuration_id,
                chart_of_accounts_id,
                currency_code,
                period_set_name,
                accounted_period_type,
                first_ledger_period_name,
                ret_earn_code_combination_id,
                suspense_allowed_flag,
                allow_intercompany_post_flag,
                track_rounding_imbalance_flag,
                enable_average_balances_flag,
                cum_trans_code_combination_id,
                res_encumb_code_combination_id,
                net_income_code_combination_id,
                rounding_code_combination_id,
                enable_budgetary_control_flag,
                require_budget_journals_flag,
                enable_je_approval_flag,
                enable_automatic_tax_flag,
                consolidation_ledger_flag,
                translate_eod_flag,
                translate_qatd_flag,
                translate_yatd_flag,
                transaction_calendar_id,
                daily_translation_rate_type,
                automatically_created_flag,
                bal_seg_value_option_code,
                bal_seg_column_name,
                mgt_seg_value_option_code,
                mgt_seg_column_name,
                bal_seg_value_set_id,
                mgt_seg_value_set_id,
                implicit_access_set_id,
                criteria_set_id,
                future_enterable_periods_limit,
                ledger_attributes,
                implicit_ledger_set_id,
                latest_opened_period_name,
                latest_encumbrance_year,
                period_average_rate_type,
                period_end_rate_type,
                budget_period_avg_rate_type,
                budget_period_end_rate_type,
                sla_accounting_method_code,
                sla_accounting_method_type,
                sla_description_language,
                sla_entered_cur_bal_sus_ccid,
                sla_sequencing_flag,
                sla_bal_by_ledger_curr_flag,
                sla_ledger_cur_bal_sus_ccid,
                enable_secondary_track_flag,
                enable_reval_ss_track_flag,
                enable_reconciliation_flag,
                create_je_flag,
                sla_ledger_cash_basis_flag,
                complete_flag,
                commitment_budget_flag,
                net_closing_bal_flag,
                automate_sec_jrnl_rev_flag,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                context,
                attribute6,
                attribute7,
                attribute8,
                attribute9,
                attribute10,
                attribute11,
                attribute12,
                attribute13,
                attribute14,
                attribute15,
                attribute_category,
                attribute_number1,
                attribute_number2,
                attribute_number3,
                attribute_number4,
                attribute_number5,
                to_char(to_date(substr(x.attribute_date1, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.attribute_date2, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.attribute_date3, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.attribute_date4, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.attribute_date5, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                object_version_number,
                ussgl_option_code,
                validate_journal_ref_date,
                jrnls_group_by_date_flag,
                reval_from_pri_lgr_curr,
                autorev_after_open_prd_flag,
                prior_prd_notification_flag,
                pop_up_stat_account_flag,
                threshold_amount,
                number_of_processors,
                processing_unit_size,
                release_upgrade_from,
                cross_lgr_clr_acc_ccid,
                interco_gain_loss_ccid,
                sequencing_mode_code,
                doc_sequencing_option_code,
                enf_seq_date_correlation_code,
                ar_doc_sequencing_option_flag,
                ap_doc_sequencing_option_flag,
                minimum_threshold_amount,
                strict_period_close_flag,
                income_stmt_adb_status_code
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        ledger_id NUMBER PATH './LEDGER_ID',
                        description VARCHAR2(240) PATH './DESCRIPTION',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        name VARCHAR2(240) PATH './NAME',
                        short_name VARCHAR2(240) PATH './SHORT_NAME',
                        ledger_category_code VARCHAR2(240) PATH './LEDGER_CATEGORY_CODE',
                        alc_ledger_type_code VARCHAR2(240) PATH './ALC_LEDGER_TYPE_CODE',
                        object_type_code VARCHAR2(240) PATH './OBJECT_TYPE_CODE',
                        le_ledger_type_code VARCHAR2(240) PATH './LE_LEDGER_TYPE_CODE',
                        completion_status_code VARCHAR2(240) PATH './COMPLETION_STATUS_CODE',
                        configuration_id NUMBER PATH './CONFIGURATION_ID',
                        chart_of_accounts_id NUMBER PATH './CHART_OF_ACCOUNTS_ID',
                        currency_code VARCHAR2(240) PATH './CURRENCY_CODE',
                        period_set_name VARCHAR2(240) PATH './PERIOD_SET_NAME',
                        accounted_period_type VARCHAR2(240) PATH './ACCOUNTED_PERIOD_TYPE',
                        first_ledger_period_name VARCHAR2(240) PATH './FIRST_LEDGER_PERIOD_NAME',
                        ret_earn_code_combination_id NUMBER PATH './RET_EARN_CODE_COMBINATION_ID',
                        suspense_allowed_flag VARCHAR2(240) PATH './SUSPENSE_ALLOWED_FLAG',
                        allow_intercompany_post_flag VARCHAR2(240) PATH './ALLOW_INTERCOMPANY_POST_FLAG',
                        track_rounding_imbalance_flag VARCHAR2(240) PATH './TRACK_ROUNDING_IMBALANCE_FLAG',
                        enable_average_balances_flag VARCHAR2(240) PATH './ENABLE_AVERAGE_BALANCES_FLAG',
                        cum_trans_code_combination_id NUMBER PATH './CUM_TRANS_CODE_COMBINATION_ID',
                        res_encumb_code_combination_id NUMBER PATH './RES_ENCUMB_CODE_COMBINATION_ID',
                        net_income_code_combination_id NUMBER PATH './NET_INCOME_CODE_COMBINATION_ID',
                        rounding_code_combination_id NUMBER PATH './ROUNDING_CODE_COMBINATION_ID',
                        enable_budgetary_control_flag VARCHAR2(240) PATH './ENABLE_BUDGETARY_CONTROL_FLAG',
                        require_budget_journals_flag VARCHAR2(240) PATH './REQUIRE_BUDGET_JOURNALS_FLAG',
                        enable_je_approval_flag VARCHAR2(240) PATH './ENABLE_JE_APPROVAL_FLAG',
                        enable_automatic_tax_flag VARCHAR2(240) PATH './ENABLE_AUTOMATIC_TAX_FLAG',
                        consolidation_ledger_flag VARCHAR2(240) PATH './CONSOLIDATION_LEDGER_FLAG',
                        translate_eod_flag VARCHAR2(240) PATH './TRANSLATE_EOD_FLAG',
                        translate_qatd_flag VARCHAR2(240) PATH './TRANSLATE_QATD_FLAG',
                        translate_yatd_flag VARCHAR2(240) PATH './TRANSLATE_YATD_FLAG',
                        transaction_calendar_id NUMBER PATH './TRANSACTION_CALENDAR_ID',
                        daily_translation_rate_type VARCHAR2(240) PATH './DAILY_TRANSLATION_RATE_TYPE',
                        automatically_created_flag VARCHAR2(240) PATH './AUTOMATICALLY_CREATED_FLAG',
                        bal_seg_value_option_code VARCHAR2(240) PATH './BAL_SEG_VALUE_OPTION_CODE',
                        bal_seg_column_name VARCHAR2(240) PATH './BAL_SEG_COLUMN_NAME',
                        mgt_seg_value_option_code VARCHAR2(240) PATH './MGT_SEG_VALUE_OPTION_CODE',
                        mgt_seg_column_name VARCHAR2(240) PATH './MGT_SEG_COLUMN_NAME',
                        bal_seg_value_set_id NUMBER PATH './BAL_SEG_VALUE_SET_ID',
                        mgt_seg_value_set_id NUMBER PATH './MGT_SEG_VALUE_SET_ID',
                        implicit_access_set_id NUMBER PATH './IMPLICIT_ACCESS_SET_ID',
                        criteria_set_id NUMBER PATH './CRITERIA_SET_ID',
                        future_enterable_periods_limit NUMBER PATH './FUTURE_ENTERABLE_PERIODS_LIMIT',
                        ledger_attributes VARCHAR2(2000) PATH './LEDGER_ATTRIBUTES',
                        implicit_ledger_set_id NUMBER PATH './IMPLICIT_LEDGER_SET_ID',
                        latest_opened_period_name VARCHAR2(240) PATH './LATEST_OPENED_PERIOD_NAME',
                        latest_encumbrance_year NUMBER PATH './LATEST_ENCUMBRANCE_YEAR',
                        period_average_rate_type VARCHAR2(240) PATH './PERIOD_AVERAGE_RATE_TYPE',
                        period_end_rate_type VARCHAR2(240) PATH './PERIOD_END_RATE_TYPE',
                        budget_period_avg_rate_type VARCHAR2(240) PATH './BUDGET_PERIOD_AVG_RATE_TYPE',
                        budget_period_end_rate_type VARCHAR2(240) PATH './BUDGET_PERIOD_END_RATE_TYPE',
                        sla_accounting_method_code VARCHAR2(240) PATH './SLA_ACCOUNTING_METHOD_CODE',
                        sla_accounting_method_type VARCHAR2(240) PATH './SLA_ACCOUNTING_METHOD_TYPE',
                        sla_description_language VARCHAR2(240) PATH './SLA_DESCRIPTION_LANGUAGE',
                        sla_entered_cur_bal_sus_ccid NUMBER PATH './SLA_ENTERED_CUR_BAL_SUS_CCID',
                        sla_sequencing_flag VARCHAR2(240) PATH './SLA_SEQUENCING_FLAG',
                        sla_bal_by_ledger_curr_flag VARCHAR2(240) PATH './SLA_BAL_BY_LEDGER_CURR_FLAG',
                        sla_ledger_cur_bal_sus_ccid VARCHAR2(240) PATH './SLA_LEDGER_CUR_BAL_SUS_CCID',
                        enable_secondary_track_flag VARCHAR2(240) PATH './ENABLE_SECONDARY_TRACK_FLAG',
                        enable_reval_ss_track_flag VARCHAR2(240) PATH './ENABLE_REVAL_SS_TRACK_FLAG',
                        enable_reconciliation_flag VARCHAR2(240) PATH './ENABLE_RECONCILIATION_FLAG',
                        create_je_flag VARCHAR2(240) PATH './CREATE_JE_FLAG',
                        sla_ledger_cash_basis_flag VARCHAR2(240) PATH './SLA_LEDGER_CASH_BASIS_FLAG',
                        complete_flag VARCHAR2(240) PATH './COMPLETE_FLAG',
                        commitment_budget_flag VARCHAR2(240) PATH './COMMITMENT_BUDGET_FLAG',
                        net_closing_bal_flag VARCHAR2(240) PATH './NET_CLOSING_BAL_FLAG',
                        automate_sec_jrnl_rev_flag VARCHAR2(240) PATH './AUTOMATE_SEC_JRNL_REV_FLAG',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        context VARCHAR2(240) PATH './CONTEXT',
                        attribute6 VARCHAR2(240) PATH './ATTRIBUTE6',
                        attribute7 VARCHAR2(240) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(240) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(240) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(240) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(240) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(240) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(240) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(240) PATH './ATTRIBUTE14',
                        attribute15 VARCHAR2(240) PATH './ATTRIBUTE15',
                        attribute_category VARCHAR2(240) PATH './ATTRIBUTE_CATEGORY',
                        attribute_number1 NUMBER PATH './ATTRIBUTE_NUMBER1',
                        attribute_number2 NUMBER PATH './ATTRIBUTE_NUMBER2',
                        attribute_number3 NUMBER PATH './ATTRIBUTE_NUMBER3',
                        attribute_number4 NUMBER PATH './ATTRIBUTE_NUMBER4',
                        attribute_number5 NUMBER PATH './ATTRIBUTE_NUMBER5',
                        attribute_date1 VARCHAR2(240) PATH './ATTRIBUTE_DATE1',
                        attribute_date2 VARCHAR2(240) PATH './ATTRIBUTE_DATE2',
                        attribute_date3 VARCHAR2(240) PATH './ATTRIBUTE_DATE3',
                        attribute_date4 VARCHAR2(240) PATH './ATTRIBUTE_DATE4',
                        attribute_date5 VARCHAR2(240) PATH './ATTRIBUTE_DATE5',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        ussgl_option_code VARCHAR2(240) PATH './USSGL_OPTION_CODE',
                        validate_journal_ref_date VARCHAR2(240) PATH './VALIDATE_JOURNAL_REF_DATE',
                        jrnls_group_by_date_flag VARCHAR2(240) PATH './JRNLS_GROUP_BY_DATE_FLAG',
                        reval_from_pri_lgr_curr VARCHAR2(240) PATH './REVAL_FROM_PRI_LGR_CURR',
                        autorev_after_open_prd_flag VARCHAR2(240) PATH './AUTOREV_AFTER_OPEN_PRD_FLAG',
                        prior_prd_notification_flag VARCHAR2(240) PATH './PRIOR_PRD_NOTIFICATION_FLAG',
                        pop_up_stat_account_flag VARCHAR2(240) PATH './POP_UP_STAT_ACCOUNT_FLAG',
                        threshold_amount NUMBER PATH './THRESHOLD_AMOUNT',
                        number_of_processors NUMBER PATH './NUMBER_OF_PROCESSORS',
                        processing_unit_size NUMBER PATH './PROCESSING_UNIT_SIZE',
                        release_upgrade_from VARCHAR2(240) PATH './RELEASE_UPGRADE_FROM',
                        cross_lgr_clr_acc_ccid NUMBER PATH './CROSS_LGR_CLR_ACC_CCID',
                        interco_gain_loss_ccid NUMBER PATH './INTERCO_GAIN_LOSS_CCID',
                        sequencing_mode_code VARCHAR2(240) PATH './SEQUENCING_MODE_CODE',
                        doc_sequencing_option_code VARCHAR2(240) PATH './DOC_SEQUENCING_OPTION_CODE',
                        enf_seq_date_correlation_code VARCHAR2(240) PATH './ENF_SEQ_DATE_CORRELATION_CODE',
                        ar_doc_sequencing_option_flag VARCHAR2(240) PATH './AR_DOC_SEQUENCING_OPTION_FLAG',
                        ap_doc_sequencing_option_flag VARCHAR2(240) PATH './AP_DOC_SEQUENCING_OPTION_FLAG',
                        minimum_threshold_amount NUMBER PATH './MINIMUM_THRESHOLD_AMOUNT',
                        strict_period_close_flag VARCHAR2(240) PATH './STRICT_PERIOD_CLOSE_FLAG',
                        income_stmt_adb_status_code VARCHAR2(240) PATH './INCOME_STMT_ADB_STATUS_CODE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_GL_LEDGER'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        gl_ledgers l
                    WHERE
                        l.ledger_id = x.ledger_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_gl_ledgers_insert_update', p_tracker =>
            'agis_gl_ledgers_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_gl_ledgers_insert_update');
    END agis_gl_ledgers_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_INTERCO_ORGANIZATIONS_INSERT_UPDATE
	*
	*  Description:  Syncs Interco Organizations BIP Report into XXAGIS_FUN_INTERCO_ORGANIZATIONS table
	*
	**************************************************************************/

    PROCEDURE agis_interco_organizations_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            interco_org_id             xxagis_fun_interco_organizations.interco_org_id%TYPE,
            description                xxagis_fun_interco_organizations.description%TYPE,
            creation_date              xxagis_fun_interco_organizations.creation_date%TYPE,
            created_by                 xxagis_fun_interco_organizations.created_by%TYPE,
            last_update_date           xxagis_fun_interco_organizations.last_update_date%TYPE,
            last_updated_by            xxagis_fun_interco_organizations.last_updated_by%TYPE,
            last_update_login          xxagis_fun_interco_organizations.last_update_login%TYPE,
            interco_org_name           xxagis_fun_interco_organizations.interco_org_name%TYPE,
            legal_entity_id            xxagis_fun_interco_organizations.legal_entity_id%TYPE,
            pay_bu_id                  xxagis_fun_interco_organizations.pay_bu_id%TYPE,
            rec_bu_id                  xxagis_fun_interco_organizations.rec_bu_id%TYPE,
            enabled_flag               xxagis_fun_interco_organizations.enabled_flag%TYPE,
            contact_person_id          xxagis_fun_interco_organizations.contact_person_id%TYPE,
            remote_instance_flag       xxagis_fun_interco_organizations.remote_instance_flag%TYPE,
            remote_instance_identifier xxagis_fun_interco_organizations.remote_instance_identifier%TYPE,
            attribute_category         xxagis_fun_interco_organizations.attribute_category%TYPE,
            object_version_number      xxagis_fun_interco_organizations.object_version_number%TYPE,
            attribute1                 xxagis_fun_interco_organizations.attribute1%TYPE,
            attribute2                 xxagis_fun_interco_organizations.attribute2%TYPE,
            attribute3                 xxagis_fun_interco_organizations.attribute3%TYPE,
            attribute4                 xxagis_fun_interco_organizations.attribute4%TYPE,
            attribute5                 xxagis_fun_interco_organizations.attribute5%TYPE,
            attribute6                 xxagis_fun_interco_organizations.attribute6%TYPE,
            attribute7                 xxagis_fun_interco_organizations.attribute7%TYPE,
            attribute8                 xxagis_fun_interco_organizations.attribute8%TYPE,
            attribute9                 xxagis_fun_interco_organizations.attribute9%TYPE,
            attribute10                xxagis_fun_interco_organizations.attribute10%TYPE,
            attribute11                xxagis_fun_interco_organizations.attribute11%TYPE,
            attribute12                xxagis_fun_interco_organizations.attribute12%TYPE,
            attribute13                xxagis_fun_interco_organizations.attribute13%TYPE,
            attribute14                xxagis_fun_interco_organizations.attribute14%TYPE,
            attribute15                xxagis_fun_interco_organizations.attribute15%TYPE,
            attribute16                xxagis_fun_interco_organizations.attribute16%TYPE,
            attribute17                xxagis_fun_interco_organizations.attribute17%TYPE,
            attribute18                xxagis_fun_interco_organizations.attribute18%TYPE,
            attribute19                xxagis_fun_interco_organizations.attribute19%TYPE,
            attribute20                xxagis_fun_interco_organizations.attribute20%TYPE,
            currency_code              xxagis_fun_interco_organizations.currency_code%TYPE,
            ledger_id                  xxagis_fun_interco_organizations.ledger_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'xxagis_fun_interco_organizations', 'STATEMENT', 'Procedure running for report : AGIS_INTERCO_ORGANIZATIONS',
        'AGIS_INTERCO_ORGANIZATIONS');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.INTERCO_ORG_ID
				,x.DESCRIPTION
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.INTERCO_ORG_NAME
				,x.LEGAL_ENTITY_ID
				,x.PAY_BU_ID
				,x.REC_BU_ID
				,x.ENABLED_FLAG
				,x.CONTACT_PERSON_ID
				,x.REMOTE_INSTANCE_FLAG
				,x.REMOTE_INSTANCE_IDENTIFIER
				,ATTRIBUTE_CATEGORY                        
				,OBJECT_VERSION_NUMBER
				,ATTRIBUTE1                           
				,ATTRIBUTE2                           
				,ATTRIBUTE3                           
				,ATTRIBUTE4                           
				,ATTRIBUTE5                           
				,ATTRIBUTE6        
				,ATTRIBUTE7                            
				,ATTRIBUTE8 
				,ATTRIBUTE9                           
				,ATTRIBUTE10                          
				,ATTRIBUTE11                          
				,ATTRIBUTE12                          
				,ATTRIBUTE13                          
				,ATTRIBUTE14                         
				,ATTRIBUTE15
				,ATTRIBUTE16
				,ATTRIBUTE17
				,ATTRIBUTE18
				,ATTRIBUTE19
				,ATTRIBUTE20		
				,CURRENCY_CODE      	
				,LEDGER_ID
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										INTERCO_ORG_ID NUMBER PATH ''./INTERCO_ORG_ID''
										,DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION''
										,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										,INTERCO_ORG_NAME VARCHAR2(240) PATH ''./INTERCO_ORG_NAME''
										,LEGAL_ENTITY_ID NUMBER PATH ''./LEGAL_ENTITY_ID''
										,PAY_BU_ID NUMBER PATH ''./PAY_BU_ID''
										,REC_BU_ID NUMBER PATH ''./REC_BU_ID''
										,ENABLED_FLAG VARCHAR2(240) PATH ''./ENABLED_FLAG''
										,CONTACT_PERSON_ID NUMBER PATH ''./CONTACT_PERSON_ID''
										,REMOTE_INSTANCE_FLAG VARCHAR2(240) PATH ''./REMOTE_INSTANCE_FLAG''
										,REMOTE_INSTANCE_IDENTIFIER VARCHAR2(240) PATH ''./REMOTE_INSTANCE_IDENTIFIER''
										,ATTRIBUTE_CATEGORY VARCHAR2(240) PATH ''./ATTRIBUTE_CATEGORY''   
										,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER''  
										,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''                           
										,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''                           
										,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''                           
										,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''                           
										,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''                           
										,ATTRIBUTE6 VARCHAR2(240) PATH ''./ATTRIBUTE6''        
										,ATTRIBUTE7 VARCHAR2(240) PATH ''./ATTRIBUTE7''                            
										,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8''
										,ATTRIBUTE9 VARCHAR2(240) PATH ''./ATTRIBUTE9''
										,ATTRIBUTE10 VARCHAR2(240) PATH ''./ATTRIBUTE10''                          
										,ATTRIBUTE11 VARCHAR2(240) PATH ''./ATTRIBUTE11''                         
										,ATTRIBUTE12 VARCHAR2(240) PATH ''./ATTRIBUTE12''                         
										,ATTRIBUTE13 VARCHAR2(240) PATH ''./ATTRIBUTE13''                         
										,ATTRIBUTE14 VARCHAR2(240) PATH ''./ATTRIBUTE14''                        
										,ATTRIBUTE15 VARCHAR2(240) PATH ''./ATTRIBUTE15''
										,ATTRIBUTE16 VARCHAR2(240) PATH ''./ATTRIBUTE16''                         
										,ATTRIBUTE17 VARCHAR2(240) PATH ''./ATTRIBUTE17''                         
										,ATTRIBUTE18 VARCHAR2(240) PATH ''./ATTRIBUTE18''                         
										,ATTRIBUTE19 VARCHAR2(240) PATH ''./ATTRIBUTE19''                        
										,ATTRIBUTE20 VARCHAR2(240) PATH ''./ATTRIBUTE20''								
										,CURRENCY_CODE VARCHAR2(240) PATH ''./CURRENCY_CODE''	
										,LEDGER_ID NUMBER PATH ''./LEDGER_ID''	
										  ) x
				WHERE t.template_name LIKE ''AGIS_INTERCO_ORGANIZATIONS''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_FUN_INTERCO_ORGANIZATIONS  L WHERE L.INTERCO_ORG_ID = x.INTERCO_ORG_ID)' ); 

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_fun_interco_organizations
            SET
                interco_org_id = agis_lookup_xml_data_rec.interco_org_id,
                description = agis_lookup_xml_data_rec.description,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                interco_org_name = agis_lookup_xml_data_rec.interco_org_name,
                legal_entity_id = agis_lookup_xml_data_rec.legal_entity_id,
                pay_bu_id = agis_lookup_xml_data_rec.pay_bu_id,
                rec_bu_id = agis_lookup_xml_data_rec.rec_bu_id,
                enabled_flag = agis_lookup_xml_data_rec.enabled_flag,
                contact_person_id = agis_lookup_xml_data_rec.contact_person_id,
                remote_instance_flag = agis_lookup_xml_data_rec.remote_instance_flag,
                remote_instance_identifier = agis_lookup_xml_data_rec.remote_instance_identifier,
                attribute_category = agis_lookup_xml_data_rec.attribute_category,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                attribute16 = agis_lookup_xml_data_rec.attribute16,
                attribute17 = agis_lookup_xml_data_rec.attribute17,
                attribute18 = agis_lookup_xml_data_rec.attribute18,
                attribute19 = agis_lookup_xml_data_rec.attribute19,
                attribute20 = agis_lookup_xml_data_rec.attribute20,
                currency_code = agis_lookup_xml_data_rec.currency_code,
                ledger_id = agis_lookup_xml_data_rec.ledger_id
            WHERE
                interco_org_id = agis_lookup_xml_data_rec.interco_org_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_fun_interco_organizations (
            interco_org_id,
            description,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            interco_org_name,
            legal_entity_id,
            pay_bu_id,
            rec_bu_id,
            enabled_flag,
            contact_person_id,
            remote_instance_flag,
            remote_instance_identifier,
            attribute_category,
            object_version_number,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute15,
            attribute16,
            attribute17,
            attribute18,
            attribute19,
            attribute20,
            currency_code,
            ledger_id
        )
            ( SELECT
                x.interco_org_id,
                x.description,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.interco_org_name,
                x.legal_entity_id,
                x.pay_bu_id,
                x.rec_bu_id,
                x.enabled_flag,
                x.contact_person_id,
                x.remote_instance_flag,
                x.remote_instance_identifier,
                attribute_category,
                object_version_number,
                attribute1,
                attribute2,
                attribute3,
                attribute4,
                attribute5,
                attribute6,
                attribute7,
                attribute8,
                attribute9,
                attribute10,
                attribute11,
                attribute12,
                attribute13,
                attribute14,
                attribute15,
                attribute16,
                attribute17,
                attribute18,
                attribute19,
                attribute20,
                currency_code,
                ledger_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        interco_org_id NUMBER PATH './INTERCO_ORG_ID',
                        description VARCHAR2(500) PATH './DESCRIPTION',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        interco_org_name VARCHAR2(240) PATH './INTERCO_ORG_NAME',
                        legal_entity_id NUMBER PATH './LEGAL_ENTITY_ID',
                        pay_bu_id NUMBER PATH './PAY_BU_ID',
                        rec_bu_id NUMBER PATH './REC_BU_ID',
                        enabled_flag VARCHAR2(240) PATH './ENABLED_FLAG',
                        contact_person_id NUMBER PATH './CONTACT_PERSON_ID',
                        remote_instance_flag VARCHAR2(240) PATH './REMOTE_INSTANCE_FLAG',
                        remote_instance_identifier VARCHAR2(240) PATH './REMOTE_INSTANCE_IDENTIFIER',
                        attribute_category VARCHAR2(240) PATH './ATTRIBUTE_CATEGORY',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        attribute6 VARCHAR2(240) PATH './ATTRIBUTE6',
                        attribute7 VARCHAR2(240) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(240) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(240) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(240) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(240) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(240) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(240) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(240) PATH './ATTRIBUTE14',
                        attribute15 VARCHAR2(240) PATH './ATTRIBUTE15',
                        attribute16 VARCHAR2(240) PATH './ATTRIBUTE16',
                        attribute17 VARCHAR2(240) PATH './ATTRIBUTE17',
                        attribute18 VARCHAR2(240) PATH './ATTRIBUTE18',
                        attribute19 VARCHAR2(240) PATH './ATTRIBUTE19',
                        attribute20 VARCHAR2(240) PATH './ATTRIBUTE20',
                        currency_code VARCHAR2(240) PATH './CURRENCY_CODE',
                        ledger_id VARCHAR2(240) PATH './LEDGER_ID'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_INTERCO_ORGANIZATIONS'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_fun_interco_organizations l
                    WHERE
                        l.interco_org_id = x.interco_org_id
                )
            );

	--CEN-8040 starts
	DELETE FROM XXAGIS_FUN_INTERCO_ORGANIZATIONS 
	WHERE ROWID IN 
		(SELECT ROWID 
			FROM
				(SELECT ROWID,
						INTERCO_ORG_ID,
						ROW_NUMBER() OVER(PARTITION BY INTERCO_ORG_ID ORDER BY LAST_UPDATE_DATE DESC) ROWN 
					FROM XXAGIS_FUN_INTERCO_ORGANIZATIONS
				)
			WHERE ROWN > 1
		) ;
	COMMIT ;
	--CEN-8040 ends

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_interco_organizations_insert_update',
            p_tracker => 'agis_interco_organizations_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_interco_organizations_insert_update');
    END agis_interco_organizations_insert_update;

    FUNCTION get_agis_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB AS                                -- BSR1827102_SR 3-30826230451 starts
        v_clob CLOB;
    BEGIN
        SELECT
            clob_details
        INTO v_clob
        FROM
            xxagis_clob_oic
        WHERE
                file_id = file_id_p
            AND file_source = 'AGIS';

        RETURN v_clob;
    exception
    when others then
    writetolog('xxagis_utility_pkg', 'get_agis_csv_data', file_id_p, dbms_utility.format_error_stack||': '||dbms_utility.format_error_backtrace,
            'EXCEPTION');
    END;

    PROCEDURE generate_agis_csv_data (
	-- FUNCTION get_agis_csv_data (                    BSR1827102_SR 3-30826230451  
        file_id_p NUMBER
    ) AS
                                                       -- BSR1827102_SR 3-30826230451  ends
        CURSOR control_cur IS
        SELECT
            *
        FROM
            xxagis_fun_interface_controls
        WHERE
            control_id = file_id_p;

        CURSOR batch_cur (
            control_id_p NUMBER
        ) IS
        SELECT
            *
        FROM
            xxagis_fun_interface_batches
        WHERE
            control_id = control_id_p
        ORDER BY
            interface_line_number;

        CURSOR header_cur (
            batch_id_p NUMBER
        ) IS
        SELECT
            *
        FROM
            xxagis_fun_interface_headers
        WHERE
            batch_id = batch_id_p
        ORDER BY
            interface_line_number;

        CURSOR lines_cur (
            header_id_p NUMBER
        ) IS
        SELECT
            *
        FROM
            xxagis_fun_interface_dist_lines
        WHERE
            header_id = header_id_p
        ORDER BY
            interface_line_number;

        CURSOR batchdist_cur (
            batch_id_p NUMBER
        ) IS
        SELECT
            *
        FROM
            xxagis_fun_interface_batchdists
        WHERE
            batch_id = batch_id_p
        ORDER BY
            interface_line_number;

        delimiter VARCHAR2(1) := ',';
        v_clob    CLOB;
    BEGIN
        dbms_lob.createtemporary(v_clob, false, dbms_lob.call);
        dbms_lob.open(v_clob, dbms_lob.lob_readwrite);
        FOR contr IN control_cur LOOP
				-- write control line to the CSV clob
            dbms_lob.writeappend(v_clob, length(contr.interface_line_code
                                                || delimiter
                                                || contr.source
                                                || delimiter
                                                || ',,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,'
                                                || chr(13)
                                                || chr(10)), contr.interface_line_code
                                                             || delimiter
                                                             || contr.source
                                                             || delimiter
                                                             || ',,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,'
                                                             || chr(13)
                                                             || chr(10));

	-- write batch line to the CSV clob

            FOR batches IN batch_cur(contr.control_id) LOOP
                dbms_lob.writeappend(v_clob, length(batches.interface_line_code
                                                    || delimiter
                                                    || batches.source
                                                    || delimiter
                                                    || batches.batch_number
                                                    || delimiter
                                                    || batches.initiator_name
                                                    || delimiter
                                                    || batches.trx_type_code
                                                    || delimiter
                                                    || batches.trx_type_name
                                                    || delimiter
                                                    || to_char(batches.batch_date, 'yyyy/mm/dd')
                                                    || delimiter
                                                    || to_char(batches.gl_date, 'yyyy/mm/dd')
                                                    || delimiter
                                                    || batches.currency_code
                                                    || delimiter
                                                    || '"'
                                                    || replace(replace(batches.description, chr(13), ' '), chr(10), ' ')
                                                    || '"'
                                                    || delimiter
                                                    || batches.note
                                                    || delimiter
                                                    || batches.control_total
                                                    || delimiter
                                                    || batches.exchange_rate_type
                                                    || delimiter
                                                    || batches.attribute_category
                                                    || delimiter
                                                    || batches.attribute1
                                                    || delimiter
                                                    || batches.attribute2
                                                    || delimiter
                                                    || batches.attribute3
                                                    || delimiter
                                                    || batches.attribute4
                                                    || delimiter
                                                    || batches.attribute5
                                                    || delimiter
                                                    || batches.attribute6
                                                    || delimiter
                                                    || batches.attribute7
                                                    || delimiter
                                                    || batches.attribute8
                                                    || delimiter
                                                    || batches.attribute9
                                                    || delimiter
                                                    || batches.attribute10
                                                    || delimiter
                                                    || batches.attribute11
                                                    || delimiter
                                                    || batches.attribute12
                                                    || delimiter
                                                    || batches.attribute13
                                                    || delimiter
                                                    || batches.attribute14
                                                    || delimiter
                                                    || batches.attribute15
                                                    || delimiter
                                                    || ',,,,,,,,,,,,,,,,,,,,,,,'
                                                    || chr(13)
                                                    || chr(10)), batches.interface_line_code
                                                                 || delimiter
                                                                 || batches.source
                                                                 || delimiter
                                                                 || batches.batch_number
                                                                 || delimiter
                                                                 || batches.initiator_name
                                                                 || delimiter
                                                                 || batches.trx_type_code
                                                                 || delimiter
                                                                 || batches.trx_type_name
                                                                 || delimiter
                                                                 || to_char(batches.batch_date, 'yyyy/mm/dd')
                                                                 || delimiter
                                                                 || to_char(batches.gl_date, 'yyyy/mm/dd')
                                                                 || delimiter
                                                                 || batches.currency_code
                                                                 || delimiter
                                                                 || replace(replace(batches.description, chr(13), ' '), chr(10), ' ')
                                                                 || delimiter
                                                                 || '"'
                                                                 || batches.note
                                                                 || '"'
                                                                 || delimiter
                                                                 || batches.control_total
                                                                 || delimiter
                                                                 || batches.exchange_rate_type
                                                                 || delimiter
                                                                 || batches.attribute_category
                                                                 || delimiter
                                                                 || batches.attribute1
                                                                 || delimiter
                                                                 || batches.attribute2
                                                                 || delimiter
                                                                 || batches.attribute3
                                                                 || delimiter
                                                                 || batches.attribute4
                                                                 || delimiter
                                                                 || batches.attribute5
                                                                 || delimiter
                                                                 || batches.attribute6
                                                                 || delimiter
                                                                 || batches.attribute7
                                                                 || delimiter
                                                                 || batches.attribute8
                                                                 || delimiter
                                                                 || batches.attribute9
                                                                 || delimiter
                                                                 || batches.attribute10
                                                                 || delimiter
                                                                 || batches.attribute11
                                                                 || delimiter
                                                                 || batches.attribute12
                                                                 || delimiter
                                                                 || batches.attribute13
                                                                 || delimiter
                                                                 || batches.attribute14
                                                                 || delimiter
                                                                 || batches.attribute15
                                                                 || delimiter
                                                                 || ',,,,,,,,,,,,,,,,,,,,,,,'
                                                                 || chr(13)
                                                                 || chr(10));
	--Write Header line to the CSV clob                    

                FOR headers IN header_cur(batches.batch_id) LOOP
                    dbms_lob.writeappend(v_clob, length(headers.interface_line_code
                                                        || delimiter
                                                        || headers.trx_number
                                                        || delimiter
                                                        || headers.recipient_name
                                                        || delimiter
                                                        || to_char(headers.init_amount_dr, 'fm999999999999.90')
                                                        || delimiter
                                                        || to_char(headers.init_amount_cr, 'fm999999999999.90')
                                                        || delimiter
                                                        || '"'
                                                        || replace(replace(headers.description, chr(13), ' '), chr(10), ' ')
                                                        || '"'
                                                        || delimiter
                                                        || headers.attribute_category
                                                        || delimiter
                                                        || headers.attribute1
                                                        || delimiter
                                                        || headers.attribute2
                                                        || delimiter
                                                        || headers.attribute3
                                                        || delimiter
                                                        || headers.attribute4
                                                        || delimiter
                                                        || headers.attribute5
                                                        || delimiter
                                                        || headers.attribute6
                                                        || delimiter
                                                        || headers.attribute7
                                                        || delimiter
                                                        || headers.attribute8
                                                        || delimiter
                                                        || headers.attribute9
                                                        || delimiter
                                                        || headers.attribute10
                                                        || delimiter
                                                        || headers.attribute11
                                                        || delimiter
                                                        || headers.attribute12
                                                        || delimiter
                                                        || headers.attribute13
                                                        || delimiter
                                                        || headers.attribute14
                                                        || delimiter
                                                        || headers.attribute15
                                                        || delimiter
                                                        || ',,,,,,,,,,,,,,,,,,,,,,,,,,,,,,'
                                                        || chr(13)
                                                        || chr(10)), headers.interface_line_code
                                                                     || delimiter
                                                                     || headers.trx_number
                                                                     || delimiter
                                                                     || headers.recipient_name
                                                                     || delimiter
                                                                     || to_char(headers.init_amount_dr, 'fm999999999999.90')
                                                                     || delimiter
                                                                     || to_char(headers.init_amount_cr, 'fm999999999999.90')
                                                                     || delimiter
                                                                     || '"'
                                                                     || replace(replace(headers.description, chr(13), ' '), chr(10), ' ')
                                                                     || '"'
                                                                     || delimiter
                                                                     || headers.attribute_category
                                                                     || delimiter
                                                                     || headers.attribute1
                                                                     || delimiter
                                                                     || headers.attribute2
                                                                     || delimiter
                                                                     || headers.attribute3
                                                                     || delimiter
                                                                     || headers.attribute4
                                                                     || delimiter
                                                                     || headers.attribute5
                                                                     || delimiter
                                                                     || headers.attribute6
                                                                     || delimiter
                                                                     || headers.attribute7
                                                                     || delimiter
                                                                     || headers.attribute8
                                                                     || delimiter
                                                                     || headers.attribute9
                                                                     || delimiter
                                                                     || headers.attribute10
                                                                     || delimiter
                                                                     || headers.attribute11
                                                                     || delimiter
                                                                     || headers.attribute12
                                                                     || delimiter
                                                                     || headers.attribute13
                                                                     || delimiter
                                                                     || headers.attribute14
                                                                     || delimiter
                                                                     || headers.attribute15
                                                                     || delimiter
                                                                     || ',,,,,,,,,,,,,,,,,,,,,,,,,,,,,,'
                                                                     || chr(13)
                                                                     || chr(10));

	--Write Lines line to the CSV clob                              

                    FOR lines IN lines_cur(headers.header_id) LOOP
                        dbms_lob.writeappend(v_clob, length(lines.interface_line_code
                                                            || delimiter
                                                            || lines.dist_number
                                                            || delimiter
                                                            || lines.party_type_flag
                                                            || delimiter
                                                            || to_char(lines.amount_dr, 'fm999999999999.90')
                                                            || delimiter
                                                            || to_char(lines.amount_cr, 'fm999999999999.90')
                                                            || delimiter
                                                            || '"'
                                                            || replace(replace(lines.description, chr(13), ' '), chr(10), ' ')
                                                            || '"'
                                                            || delimiter
                                                            || lines.segment1
                                                            || delimiter
                                                            || lines.segment2
                                                            || delimiter
                                                            || lines.segment3
                                                            || delimiter
                                                            || lines.segment4
                                                            || delimiter
                                                            || lines.segment5
                                                            || delimiter
                                                            || lines.segment6
                                                            || delimiter
                                                            || lines.segment7
                                                            || delimiter
                                                            || lines.segment8
                                                            || delimiter
                                                            || lines.segment9
                                                            || delimiter
                                                            || lines.segment10
                                                            || delimiter
                                                            || lines.segment11
                                                            || delimiter
                                                            || lines.segment12
                                                            || delimiter
                                                            || lines.segment13
                                                            || delimiter
                                                            || lines.segment14
                                                            || delimiter
                                                            || lines.segment15
                                                            || delimiter
                                                            || lines.segment16
                                                            || delimiter
                                                            || lines.segment17
                                                            || delimiter
                                                            || lines.segment18
                                                            || delimiter
                                                            || lines.segment19
                                                            || delimiter
                                                            || lines.segment20
                                                            || delimiter
                                                            || lines.segment21
                                                            || delimiter
                                                            || lines.segment22
                                                            || delimiter
                                                            || lines.segment23
                                                            || delimiter
                                                            || lines.segment24
                                                            || delimiter
                                                            || lines.segment25
                                                            || delimiter
                                                            || lines.segment26
                                                            || delimiter
                                                            || lines.segment27
                                                            || delimiter
                                                            || lines.segment28
                                                            || delimiter
                                                            || lines.segment29
                                                            || delimiter
                                                            || lines.segment30
                                                            || delimiter
                                                            || lines.attribute_category
                                                            || delimiter
                                                            || lines.attribute1
                                                            || delimiter
                                                            || lines.attribute2
                                                            || delimiter
                                                            || lines.attribute3
                                                            || delimiter
                                                            || lines.attribute4
                                                            || delimiter
                                                            || lines.attribute5
                                                            || delimiter
                                                            || lines.attribute6
                                                            || delimiter
                                                            || lines.attribute7
                                                            || delimiter
                                                            || lines.attribute8
                                                            || delimiter
                                                            || lines.attribute9
                                                            || delimiter
                                                            || lines.attribute10
                                                            || delimiter
                                                            || lines.attribute11
                                                            || delimiter
                                                            || lines.attribute12
                                                            || delimiter
                                                            || lines.attribute13
                                                            || delimiter
                                                            || lines.attribute14
                                                            || delimiter
                                                            || lines.attribute15
                                                            || delimiter
                                                            || chr(13)
                                                            || chr(10)), lines.interface_line_code
                                                                         || delimiter
                                                                         || lines.dist_number
                                                                         || delimiter
                                                                         || lines.party_type_flag
                                                                         || delimiter
                                                                         || to_char(lines.amount_dr, 'fm999999999999.90')
                                                                         || delimiter
                                                                         || to_char(lines.amount_cr, 'fm999999999999.90')
                                                                         || delimiter
                                                                         || '"'
                                                                         || replace(replace(lines.description, chr(13), ' '), chr(10),
                                                                         ' ')
                                                                         || '"'
                                                                         || delimiter
                                                                         || lines.segment1
                                                                         || delimiter
                                                                         || lines.segment2
                                                                         || delimiter
                                                                         || lines.segment3
                                                                         || delimiter
                                                                         || lines.segment4
                                                                         || delimiter
                                                                         || lines.segment5
                                                                         || delimiter
                                                                         || lines.segment6
                                                                         || delimiter
                                                                         || lines.segment7
                                                                         || delimiter
                                                                         || lines.segment8
                                                                         || delimiter
                                                                         || lines.segment9
                                                                         || delimiter
                                                                         || lines.segment10
                                                                         || delimiter
                                                                         || lines.segment11
                                                                         || delimiter
                                                                         || lines.segment12
                                                                         || delimiter
                                                                         || lines.segment13
                                                                         || delimiter
                                                                         || lines.segment14
                                                                         || delimiter
                                                                         || lines.segment15
                                                                         || delimiter
                                                                         || lines.segment16
                                                                         || delimiter
                                                                         || lines.segment17
                                                                         || delimiter
                                                                         || lines.segment18
                                                                         || delimiter
                                                                         || lines.segment19
                                                                         || delimiter
                                                                         || lines.segment20
                                                                         || delimiter
                                                                         || lines.segment21
                                                                         || delimiter
                                                                         || lines.segment22
                                                                         || delimiter
                                                                         || lines.segment23
                                                                         || delimiter
                                                                         || lines.segment24
                                                                         || delimiter
                                                                         || lines.segment25
                                                                         || delimiter
                                                                         || lines.segment26
                                                                         || delimiter
                                                                         || lines.segment27
                                                                         || delimiter
                                                                         || lines.segment28
                                                                         || delimiter
                                                                         || lines.segment29
                                                                         || delimiter
                                                                         || lines.segment30
                                                                         || delimiter
                                                                         || lines.attribute_category
                                                                         || delimiter
                                                                         || lines.attribute1
                                                                         || delimiter
                                                                         || lines.attribute2
                                                                         || delimiter
                                                                         || lines.attribute3
                                                                         || delimiter
                                                                         || lines.attribute4
                                                                         || delimiter
                                                                         || lines.attribute5
                                                                         || delimiter
                                                                         || lines.attribute6
                                                                         || delimiter
                                                                         || lines.attribute7
                                                                         || delimiter
                                                                         || lines.attribute8
                                                                         || delimiter
                                                                         || lines.attribute9
                                                                         || delimiter
                                                                         || lines.attribute10
                                                                         || delimiter
                                                                         || lines.attribute11
                                                                         || delimiter
                                                                         || lines.attribute12
                                                                         || delimiter
                                                                         || lines.attribute13
                                                                         || delimiter
                                                                         || lines.attribute14
                                                                         || delimiter
                                                                         || lines.attribute15
                                                                         || delimiter
                                                                         || chr(13)
                                                                         || chr(10));
                    END LOOP;

                END LOOP;

            END LOOP;

        END LOOP;
        -- BSR1827102_SR 3-30826230451 starts
		--  dbms_output.put_line(v_clob);
        -- RETURN v_clob;
        DELETE FROM xxagis_clob_oic
        WHERE
            file_id = file_id_p;

        INSERT INTO xxagis_clob_oic VALUES (
            file_id_p,
            'AGIS',
            v_clob,
            sysdate,
            sysdate
        );
        -- BSR1827102_SR 3-30826230451 ends
        COMMIT;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'generate_agis_csv_data', p_tracker => 'generate_agis_csv_data',
            p_custom_err_info => 'EXCEPTION3 : generate_agis_csv_data');
    END;

		/***************************************************************************
	*
	*  FUNCTION: GET_RA_INTERFACE_LINES_CSV_DATA
	*
	*  Description:  Used to write RA Interface Lines to the CSV clob
	*
	**************************************************************************/

    FUNCTION get_ra_interface_lines_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB AS

        CURSOR ra_interface_lines_cur IS
        SELECT
            *
        FROM
            xxagis_ra_interface_lines_all
        WHERE
            file_id = file_id_p;

        delimiter VARCHAR2(1) := ',';
        v_clob    CLOB;
    BEGIN
        dbms_lob.createtemporary(v_clob, false, dbms_lob.call);
        dbms_lob.open(v_clob, dbms_lob.lob_readwrite);

	-- write RA Interface Lines to the CSV clob
        FOR ra_lines IN ra_interface_lines_cur LOOP
            dbms_lob.writeappend(v_clob, length(delimiter
                                                || ra_lines.batch_source_name
                                                || delimiter
                                                || ra_lines.cust_trx_type_name
                                                || delimiter
                                                || ra_lines.term_name
                                                || delimiter
                                                || to_char(ra_lines.trx_date, 'yyyy/mm/dd')
                                                || delimiter
                                                || to_char(ra_lines.gl_date, 'yyyy/mm/dd')
                                                || delimiter
                                                || ra_lines.trx_number
                                                || delimiter
                                                || ra_lines.orig_system_bill_customer_ref
                                                || delimiter
                                                || ra_lines.orig_system_bill_address_ref
                                                || delimiter
                                                || ra_lines.orig_system_bill_contact_ref
                                                || delimiter
                                                || ra_lines.orig_sys_sold_party_ref
                                                || delimiter
                                                || ra_lines.orig_sys_ship_party_site_ref
                                                || delimiter
                                                || ra_lines.orig_sys_ship_pty_contact_ref
                                                || delimiter
                                                || ra_lines.orig_system_ship_customer_ref
                                                || delimiter
                                                || ra_lines.orig_system_ship_address_ref
                                                || delimiter
                                                || ra_lines.orig_system_ship_contact_ref
                                                || delimiter
                                                || ra_lines.orig_sys_sold_party_ref
                                                || delimiter
                                                || ra_lines.orig_system_sold_customer_ref
                                                || delimiter
                                                || ra_lines.bill_customer_account_number
                                                || delimiter
                                                || ra_lines.bill_customer_site_number
                                                || delimiter
                                                || ra_lines.ship_contact_party_number
                                                || delimiter
                                                || ra_lines.ship_customer_account_number
                                                || delimiter
                                                || ra_lines.ship_customer_site_number
                                                || delimiter
                                                || ra_lines.bill_contact_party_number
                                                || delimiter
                                                || ra_lines.sold_customer_account_number
                                                || delimiter
                                                || ra_lines.line_type
                                                || delimiter
                                                || replace(replace(ra_lines.description, chr(13), ' '), chr(10), ' ')
                                                || delimiter
                                                || ra_lines.currency_code
                                                || delimiter
                                                || ra_lines.conversion_type
                                                || delimiter
                                                || to_char(ra_lines.conversion_date, 'yyyy/mm/dd')
                                                || delimiter
                                                || to_char(ra_lines.conversion_rate, 'fm999999999999.90')
                                                || delimiter
                                                || to_char(ra_lines.amount, 'fm999999999999.90')
                                                || delimiter
                                                || to_char(ra_lines.quantity, 'fm999999999999.90')
                                                || delimiter
                                                || ra_lines.quantity_ordered
                                                || delimiter
                                                || to_char(ra_lines.unit_selling_price, 'fm999999999999.90')
                                                || delimiter
                                                || ra_lines.unit_standard_price
                                                || delimiter
                                                || ra_lines.interface_line_context
                                                || delimiter
                                                || ra_lines.interface_line_attribute1
                                                || delimiter
                                                || ra_lines.interface_line_attribute2
                                                || delimiter
                                                || ra_lines.interface_line_attribute3
                                                || delimiter
                                                || ra_lines.interface_line_attribute4
                                                || delimiter
                                                || ra_lines.interface_line_attribute5
                                                || delimiter
                                                || ra_lines.interface_line_attribute6
                                                || delimiter
                                                || ra_lines.interface_line_attribute7
                                                || delimiter
                                                || ra_lines.interface_line_attribute8
                                                || delimiter
                                                || ra_lines.interface_line_attribute9
                                                || delimiter
                                                || ra_lines.interface_line_attribute10
                                                || delimiter
                                                || ra_lines.interface_line_attribute11
                                                || delimiter
                                                || ra_lines.interface_line_attribute12
                                                || delimiter
                                                || ra_lines.interface_line_attribute13
                                                || delimiter
                                                || ra_lines.interface_line_attribute14
                                                || delimiter
                                                || ra_lines.interface_line_attribute15
                                                || delimiter
                                                || ra_lines.primary_salesrep_number
                                                || delimiter
                                                || ra_lines.tax_code
                                                || delimiter
                                                || ra_lines.legal_entity_identifier
                                                || delimiter
                                                || ra_lines.acctd_amount
                                                || delimiter
                                                || ra_lines.sales_order
                                                || delimiter
                                                || ra_lines.sales_order_date
                                                || delimiter
                                                || ra_lines.ship_date_actual
                                                || delimiter
                                                || ra_lines.warehouse_code
                                                || delimiter
                                                || ra_lines.uom_code
                                                || delimiter
                                                || ra_lines.uom_name
                                                || delimiter
                                                || ra_lines.invoicing_rule_name
                                                || delimiter
                                                || ra_lines.accounting_rule_name
                                                || delimiter
                                                || ra_lines.accounting_rule_duration
                                                || delimiter
                                                || ra_lines.rule_start_date
                                                || delimiter
                                                || ra_lines.rule_end_date
                                                || delimiter
                                                || ra_lines.reason_code_meaning
                                                || delimiter
                                                || ra_lines.last_period_to_credit
                                                || delimiter
                                                || ra_lines.trx_business_category
                                                || delimiter
                                                || ra_lines.product_fisc_classification
                                                || delimiter
                                                || ra_lines.product_category
                                                || delimiter
                                                || ra_lines.product_type
                                                || delimiter
                                                || ra_lines.line_intended_use
                                                || delimiter
                                                || ra_lines.assessable_value
                                                || delimiter
                                                || ra_lines.document_sub_type
                                                || delimiter
                                                || ra_lines.default_taxation_country
                                                || delimiter
                                                || ra_lines.user_defined_fisc_class
                                                || delimiter
                                                || ra_lines.tax_invoice_number
                                                || delimiter
                                                || ra_lines.tax_invoice_date
                                                || delimiter
                                                || ra_lines.tax_regime_code
                                                || delimiter
                                                || ra_lines.tax
                                                || delimiter
                                                || ra_lines.tax_status_code
                                                || delimiter
                                                || ra_lines.tax_rate_code
                                                || delimiter
                                                || ra_lines.tax_jurisdiction_code
                                                || delimiter
                                                || ra_lines.first_pty_reg_num
                                                || delimiter
                                                || ra_lines.third_pty_reg_num
                                                || delimiter
                                                || ra_lines.final_discharge_location_code
                                                || delimiter
                                                || ra_lines.taxable_amount
                                                || delimiter
                                                || ra_lines.taxable_flag
                                                || delimiter
                                                || ra_lines.tax_exempt_flag
                                                || delimiter
                                                || ra_lines.tax_exempt_reason_code
                                                || delimiter
                                                || ra_lines.tax_exempt_reason_code_meaning
                                                || delimiter
                                                || ra_lines.tax_exempt_number
                                                || delimiter
                                                || ra_lines.amount_includes_tax_flag
                                                || delimiter
                                                || ra_lines.tax_precedence
                                                || delimiter
                                                || ra_lines.credit_method_for_acct_rule
                                                || delimiter
                                                || ra_lines.credit_method_for_installments
                                                || delimiter
                                                || ra_lines.reason_code
                                                || delimiter
                                                || ra_lines.tax_rate
                                                || delimiter
                                                || ra_lines.fob_point
                                                || delimiter
                                                || ra_lines.ship_via
                                                || delimiter
                                                || ra_lines.waybill_number
                                                || delimiter
                                                || ra_lines.sales_order_line
                                                || delimiter
                                                || ra_lines.sales_order_source
                                                || delimiter
                                                || ra_lines.sales_order_revision
                                                || delimiter
                                                || ra_lines.purchase_order
                                                || delimiter
                                                || ra_lines.purchase_order_revision
                                                || delimiter
                                                || ra_lines.purchase_order_date
                                                || delimiter
                                                || ra_lines.agreement_name
                                                || delimiter
                                                || ra_lines.memo_line_name
                                                || delimiter
                                                || ra_lines.document_number
                                                || delimiter
                                                || ra_lines.orig_system_batch_name
                                                || delimiter
                                                || ra_lines.link_to_line_context
                                                || delimiter
                                                || ra_lines.link_to_line_attribute1
                                                || delimiter
                                                || ra_lines.link_to_line_attribute2
                                                || delimiter
                                                || ra_lines.link_to_line_attribute3
                                                || delimiter
                                                || ra_lines.link_to_line_attribute4
                                                || delimiter
                                                || ra_lines.link_to_line_attribute5
                                                || delimiter
                                                || ra_lines.link_to_line_attribute6
                                                || delimiter
                                                || ra_lines.link_to_line_attribute7
                                                || delimiter
                                                || ra_lines.link_to_line_attribute8
                                                || delimiter
                                                || ra_lines.link_to_line_attribute9
                                                || delimiter
                                                || ra_lines.link_to_line_attribute10
                                                || delimiter
                                                || ra_lines.link_to_line_attribute11
                                                || delimiter
                                                || ra_lines.link_to_line_attribute12
                                                || delimiter
                                                || ra_lines.link_to_line_attribute13
                                                || delimiter
                                                || ra_lines.link_to_line_attribute14
                                                || delimiter
                                                || ra_lines.link_to_line_attribute15
                                                || delimiter
                                                || ra_lines.reference_line_context
                                                || delimiter
                                                || ra_lines.reference_line_attribute1
                                                || delimiter
                                                || ra_lines.reference_line_attribute2
                                                || delimiter
                                                || ra_lines.reference_line_attribute3
                                                || delimiter
                                                || ra_lines.reference_line_attribute4
                                                || delimiter
                                                || ra_lines.reference_line_attribute5
                                                || delimiter
                                                || ra_lines.reference_line_attribute6
                                                || delimiter
                                                || ra_lines.reference_line_attribute7
                                                || delimiter
                                                || ra_lines.reference_line_attribute8
                                                || delimiter
                                                || ra_lines.reference_line_attribute9
                                                || delimiter
                                                || ra_lines.reference_line_attribute10
                                                || delimiter
                                                || ra_lines.reference_line_attribute11
                                                || delimiter
                                                || ra_lines.reference_line_attribute12
                                                || delimiter
                                                || ra_lines.reference_line_attribute13
                                                || delimiter
                                                || ra_lines.reference_line_attribute14
                                                || delimiter
                                                || ra_lines.reference_line_attribute15
                                                || delimiter
                                                || ra_lines.link_to_parentline_context
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute1
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute2
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute3
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute4
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute5
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute6
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute7
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute8
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute9
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute10
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute11
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute12
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute13
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute14
                                                || delimiter
                                                || ra_lines.link_to_parentline_attribute15
                                                || delimiter
                                                || ra_lines.receipt_method_name
                                                || delimiter
                                                || ra_lines.printing_option
                                                || delimiter
                                                || ra_lines.related_batch_source_name
                                                || delimiter
                                                || ra_lines.related_trx_number
                                                || delimiter
                                                || ra_lines.egp_system_items_seg1
                                                || delimiter
                                                || ra_lines.egp_system_items_seg2
                                                || delimiter
                                                || ra_lines.egp_system_items_seg3
                                                || delimiter
                                                || ra_lines.egp_system_items_seg4
                                                || delimiter
                                                || ra_lines.egp_system_items_seg5
                                                || delimiter
                                                || ra_lines.egp_system_items_seg6
                                                || delimiter
                                                || ra_lines.egp_system_items_seg7
                                                || delimiter
                                                || ra_lines.egp_system_items_seg8
                                                || delimiter
                                                || ra_lines.egp_system_items_seg9
                                                || delimiter
                                                || ra_lines.egp_system_items_seg10
                                                || delimiter
                                                || ra_lines.egp_system_items_seg11
                                                || delimiter
                                                || ra_lines.egp_system_items_seg12
                                                || delimiter
                                                || ra_lines.egp_system_items_seg13
                                                || delimiter
                                                || ra_lines.egp_system_items_seg14
                                                || delimiter
                                                || ra_lines.egp_system_items_seg15
                                                || delimiter
                                                || ra_lines.egp_system_items_seg16
                                                || delimiter
                                                || ra_lines.egp_system_items_seg17
                                                || delimiter
                                                || ra_lines.egp_system_items_seg18
                                                || delimiter
                                                || ra_lines.egp_system_items_seg19
                                                || delimiter
                                                || ra_lines.egp_system_items_seg20
                                                || delimiter
                                                || ra_lines.customer_bank_account_name
                                                || delimiter
                                                || ra_lines.reset_trx_date_flag
                                                || delimiter
                                                || ra_lines.payment_server_order_num
                                                || delimiter
                                                || ra_lines.last_trx_debit_auth_flag
                                                || delimiter
                                                || ra_lines.approval_code
                                                || delimiter
                                                || ra_lines.address_verification_code
                                                || delimiter
                                                || ra_lines.translated_description
                                                || delimiter
                                                || ra_lines.cons_billing_number
                                                || delimiter
                                                || ra_lines.promised_commitment_amount
                                                || delimiter
                                                || ra_lines.payment_set_id
                                                || delimiter
                                                || ra_lines.original_gl_date
                                                || delimiter
                                                || ra_lines.invoiced_line_acctg_level
                                                || delimiter
                                                || ra_lines.override_auto_accounting_flag
                                                || delimiter
                                                || ra_lines.historical_flag
                                                || delimiter
                                                || ra_lines.deferral_exclusion_flag
                                                || delimiter
                                                || ra_lines.payment_attributes
                                                || delimiter
                                                || ra_lines.billing_date
                                                || delimiter
                                                || ra_lines.attribute_category
                                                || delimiter
                                                || ra_lines.attribute1
                                                || delimiter
                                                || ra_lines.attribute2
                                                || delimiter
                                                || ra_lines.attribute3
                                                || delimiter
                                                || ra_lines.attribute4
                                                || delimiter
                                                || ra_lines.attribute5
                                                || delimiter
                                                || ra_lines.attribute6
                                                || delimiter
                                                || ra_lines.attribute7
                                                || delimiter
                                                || ra_lines.attribute8
                                                || delimiter
                                                || ra_lines.attribute9
                                                || delimiter
                                                || ra_lines.attribute10
                                                || delimiter
                                                || ra_lines.attribute11
                                                || delimiter
                                                || ra_lines.attribute12
                                                || delimiter
                                                || ra_lines.attribute13
                                                || delimiter
                                                || ra_lines.attribute14
                                                || delimiter
                                                || ra_lines.attribute15
                                                || delimiter
                                                || ra_lines.header_attribute_category
                                                || delimiter
                                                || ra_lines.header_attribute1
                                                || delimiter
                                                || ra_lines.header_attribute2
                                                || delimiter
                                                || ra_lines.header_attribute3
                                                || delimiter
                                                || ra_lines.header_attribute4
                                                || delimiter
                                                || ra_lines.header_attribute5
                                                || delimiter
                                                || ra_lines.header_attribute6
                                                || delimiter
                                                || ra_lines.header_attribute7
                                                || delimiter
                                                || ra_lines.header_attribute8
                                                || delimiter
                                                || ra_lines.header_attribute9
                                                || delimiter
                                                || ra_lines.header_attribute10
                                                || delimiter
                                                || ra_lines.header_attribute11
                                                || delimiter
                                                || ra_lines.header_attribute12
                                                || delimiter
                                                || ra_lines.header_attribute13
                                                || delimiter
                                                || ra_lines.header_attribute14
                                                || delimiter
                                                || ra_lines.header_attribute15
                                                || delimiter
                                                || ra_lines.header_gdf_attr_category
                                                || delimiter
                                                || ra_lines.header_gdf_attribute1
                                                || delimiter
                                                || ra_lines.header_gdf_attribute2
                                                || delimiter
                                                || ra_lines.header_gdf_attribute3
                                                || delimiter
                                                || ra_lines.header_gdf_attribute4
                                                || delimiter
                                                || ra_lines.header_gdf_attribute5
                                                || delimiter
                                                || ra_lines.header_gdf_attribute6
                                                || delimiter
                                                || ra_lines.header_gdf_attribute7
                                                || delimiter
                                                || ra_lines.header_gdf_attribute8
                                                || delimiter
                                                || ra_lines.header_gdf_attribute9
                                                || delimiter
                                                || ra_lines.header_gdf_attribute10
                                                || delimiter
                                                || ra_lines.header_gdf_attribute11
                                                || delimiter
                                                || ra_lines.header_gdf_attribute12
                                                || delimiter
                                                || ra_lines.header_gdf_attribute13
                                                || delimiter
                                                || ra_lines.header_gdf_attribute14
                                                || delimiter
                                                || ra_lines.header_gdf_attribute15
                                                || delimiter
                                                || ra_lines.header_gdf_attribute16
                                                || delimiter
                                                || ra_lines.header_gdf_attribute17
                                                || delimiter
                                                || ra_lines.header_gdf_attribute18
                                                || delimiter
                                                || ra_lines.header_gdf_attribute19
                                                || delimiter
                                                || ra_lines.header_gdf_attribute20
                                                || delimiter
                                                || ra_lines.header_gdf_attribute21
                                                || delimiter
                                                || ra_lines.header_gdf_attribute22
                                                || delimiter
                                                || ra_lines.header_gdf_attribute23
                                                || delimiter
                                                || ra_lines.header_gdf_attribute24
                                                || delimiter
                                                || ra_lines.header_gdf_attribute25
                                                || delimiter
                                                || ra_lines.header_gdf_attribute26
                                                || delimiter
                                                || ra_lines.header_gdf_attribute27
                                                || delimiter
                                                || ra_lines.header_gdf_attribute28
                                                || delimiter
                                                || ra_lines.header_gdf_attribute29
                                                || delimiter
                                                || ra_lines.header_gdf_attribute30
                                                || delimiter
                                                || ra_lines.line_gdf_attr_category
                                                || delimiter
                                                || ra_lines.line_gdf_attribute1
                                                || delimiter
                                                || ra_lines.line_gdf_attribute2
                                                || delimiter
                                                || ra_lines.line_gdf_attribute3
                                                || delimiter
                                                || ra_lines.line_gdf_attribute4
                                                || delimiter
                                                || ra_lines.line_gdf_attribute5
                                                || delimiter
                                                || ra_lines.line_gdf_attribute6
                                                || delimiter
                                                || ra_lines.line_gdf_attribute7
                                                || delimiter
                                                || ra_lines.line_gdf_attribute8
                                                || delimiter
                                                || ra_lines.line_gdf_attribute9
                                                || delimiter
                                                || ra_lines.line_gdf_attribute10
                                                || delimiter
                                                || ra_lines.line_gdf_attribute11
                                                || delimiter
                                                || ra_lines.line_gdf_attribute12
                                                || delimiter
                                                || ra_lines.line_gdf_attribute13
                                                || delimiter
                                                || ra_lines.line_gdf_attribute14
                                                || delimiter
                                                || ra_lines.line_gdf_attribute15
                                                || delimiter
                                                || ra_lines.line_gdf_attribute16
                                                || delimiter
                                                || ra_lines.line_gdf_attribute17
                                                || delimiter
                                                || ra_lines.line_gdf_attribute18
                                                || delimiter
                                                || ra_lines.line_gdf_attribute19
                                                || delimiter
                                                || ra_lines.line_gdf_attribute20
                                                || delimiter
                                                || ra_lines.bu_name
                                                || delimiter
                                                ||        ---Business unit Name
                                                 ra_lines.comments
                                                || delimiter
                                                || ra_lines.internal_notes
                                                || delimiter
                                                || ra_lines.cc_token_number
                                                || delimiter
                                                || ra_lines.cc_expiration_date
                                                || delimiter
                                                || ra_lines.cc_first_name
                                                || delimiter
                                                || ra_lines.cc_last_name
                                                || delimiter
                                                || ra_lines.cc_issuer_code
                                                || delimiter
                                                || ra_lines.cc_masked_number
                                                || delimiter
                                                || ra_lines.cc_auth_request_id
                                                || delimiter
                                                || ra_lines.cc_voice_auth_code
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number1
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number2
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number3
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number4
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number5
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number6
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number7
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number8
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number9
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number10
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number11
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_number12
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_date1
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_date2
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_date3
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_date4
                                                || delimiter
                                                || ra_lines.header_gdf_attribute_date5
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_number1
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_number2
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_number3
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_number4
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_number5
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_date1
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_date2
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_date3
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_date4
                                                || delimiter
                                                || ra_lines.line_gdf_attribute_date5
                                                || delimiter
                                                || ra_lines.freight_charge
                                                || delimiter
                                                || ra_lines.insurance_charge
                                                || delimiter
                                                || ra_lines.packing_charge
                                                || delimiter
                                                || ra_lines.miscellaneous_charge
                                                || delimiter
                                                || ra_lines.commercial_discount
                                                || delimiter
                                                || ra_lines.enf_seq_date_correlation_code
                                                || delimiter
                                                || ',,END'
                                                || chr(13)
                                                || chr(10)), delimiter
                                                             || ra_lines.batch_source_name
                                                             || delimiter
                                                             || ra_lines.cust_trx_type_name
                                                             || delimiter
                                                             || ra_lines.term_name
                                                             || delimiter
                                                             || to_char(ra_lines.trx_date, 'yyyy/mm/dd')
                                                             || delimiter
                                                             || to_char(ra_lines.gl_date, 'yyyy/mm/dd')
                                                             || delimiter
                                                             || ra_lines.trx_number
                                                             || delimiter
                                                             || ra_lines.orig_system_bill_customer_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_bill_address_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_bill_contact_ref
                                                             || delimiter
                                                             || ra_lines.orig_sys_sold_party_ref
                                                             || delimiter
                                                             || ra_lines.orig_sys_ship_party_site_ref
                                                             || delimiter
                                                             || ra_lines.orig_sys_ship_pty_contact_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_ship_customer_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_ship_address_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_ship_contact_ref
                                                             || delimiter
                                                             || ra_lines.orig_sys_sold_party_ref
                                                             || delimiter
                                                             || ra_lines.orig_system_sold_customer_ref
                                                             || delimiter
                                                             || ra_lines.bill_customer_account_number
                                                             || delimiter
                                                             || ra_lines.bill_customer_site_number
                                                             || delimiter
                                                             || ra_lines.ship_contact_party_number
                                                             || delimiter
                                                             || ra_lines.ship_customer_account_number
                                                             || delimiter
                                                             || ra_lines.ship_customer_site_number
                                                             || delimiter
                                                             || ra_lines.bill_contact_party_number
                                                             || delimiter
                                                             || ra_lines.sold_customer_account_number
                                                             || delimiter
                                                             || ra_lines.line_type
                                                             || delimiter
                                                             || replace(replace(ra_lines.description, chr(13), ' '), chr(10), ' ')
                                                             || delimiter
                                                             || ra_lines.currency_code
                                                             || delimiter
                                                             || ra_lines.conversion_type
                                                             || delimiter
                                                             || to_char(ra_lines.conversion_date, 'yyyy/mm/dd')
                                                             || delimiter
                                                             || to_char(ra_lines.conversion_rate, 'fm999999999999.90')
                                                             || delimiter
                                                             || to_char(ra_lines.amount, 'fm999999999999.90')
                                                             || delimiter
                                                             || to_char(ra_lines.quantity, 'fm999999999999.90')
                                                             || delimiter
                                                             || ra_lines.quantity_ordered
                                                             || delimiter
                                                             || to_char(ra_lines.unit_selling_price, 'fm999999999999.90')
                                                             || delimiter
                                                             || ra_lines.unit_standard_price
                                                             || delimiter
                                                             || ra_lines.interface_line_context
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute1
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute2
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute3
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute4
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute5
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute6
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute7
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute8
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute9
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute10
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute11
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute12
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute13
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute14
                                                             || delimiter
                                                             || ra_lines.interface_line_attribute15
                                                             || delimiter
                                                             || ra_lines.primary_salesrep_number
                                                             || delimiter
                                                             || ra_lines.tax_code
                                                             || delimiter
                                                             || ra_lines.legal_entity_identifier
                                                             || delimiter
                                                             || ra_lines.acctd_amount
                                                             || delimiter
                                                             || ra_lines.sales_order
                                                             || delimiter
                                                             || ra_lines.sales_order_date
                                                             || delimiter
                                                             || ra_lines.ship_date_actual
                                                             || delimiter
                                                             || ra_lines.warehouse_code
                                                             || delimiter
                                                             || ra_lines.uom_code
                                                             || delimiter
                                                             || ra_lines.uom_name
                                                             || delimiter
                                                             || ra_lines.invoicing_rule_name
                                                             || delimiter
                                                             || ra_lines.accounting_rule_name
                                                             || delimiter
                                                             || ra_lines.accounting_rule_duration
                                                             || delimiter
                                                             || ra_lines.rule_start_date
                                                             || delimiter
                                                             || ra_lines.rule_end_date
                                                             || delimiter
                                                             || ra_lines.reason_code_meaning
                                                             || delimiter
                                                             || ra_lines.last_period_to_credit
                                                             || delimiter
                                                             || ra_lines.trx_business_category
                                                             || delimiter
                                                             || ra_lines.product_fisc_classification
                                                             || delimiter
                                                             || ra_lines.product_category
                                                             || delimiter
                                                             || ra_lines.product_type
                                                             || delimiter
                                                             || ra_lines.line_intended_use
                                                             || delimiter
                                                             || ra_lines.assessable_value
                                                             || delimiter
                                                             || ra_lines.document_sub_type
                                                             || delimiter
                                                             || ra_lines.default_taxation_country
                                                             || delimiter
                                                             || ra_lines.user_defined_fisc_class
                                                             || delimiter
                                                             || ra_lines.tax_invoice_number
                                                             || delimiter
                                                             || ra_lines.tax_invoice_date
                                                             || delimiter
                                                             || ra_lines.tax_regime_code
                                                             || delimiter
                                                             || ra_lines.tax
                                                             || delimiter
                                                             || ra_lines.tax_status_code
                                                             || delimiter
                                                             || ra_lines.tax_rate_code
                                                             || delimiter
                                                             || ra_lines.tax_jurisdiction_code
                                                             || delimiter
                                                             || ra_lines.first_pty_reg_num
                                                             || delimiter
                                                             || ra_lines.third_pty_reg_num
                                                             || delimiter
                                                             || ra_lines.final_discharge_location_code
                                                             || delimiter
                                                             || ra_lines.taxable_amount
                                                             || delimiter
                                                             || ra_lines.taxable_flag
                                                             || delimiter
                                                             || ra_lines.tax_exempt_flag
                                                             || delimiter
                                                             || ra_lines.tax_exempt_reason_code
                                                             || delimiter
                                                             || ra_lines.tax_exempt_reason_code_meaning
                                                             || delimiter
                                                             || ra_lines.tax_exempt_number
                                                             || delimiter
                                                             || ra_lines.amount_includes_tax_flag
                                                             || delimiter
                                                             || ra_lines.tax_precedence
                                                             || delimiter
                                                             || ra_lines.credit_method_for_acct_rule
                                                             || delimiter
                                                             || ra_lines.credit_method_for_installments
                                                             || delimiter
                                                             || ra_lines.reason_code
                                                             || delimiter
                                                             || ra_lines.tax_rate
                                                             || delimiter
                                                             || ra_lines.fob_point
                                                             || delimiter
                                                             || ra_lines.ship_via
                                                             || delimiter
                                                             || ra_lines.waybill_number
                                                             || delimiter
                                                             || ra_lines.sales_order_line
                                                             || delimiter
                                                             || ra_lines.sales_order_source
                                                             || delimiter
                                                             || ra_lines.sales_order_revision
                                                             || delimiter
                                                             || ra_lines.purchase_order
                                                             || delimiter
                                                             || ra_lines.purchase_order_revision
                                                             || delimiter
                                                             || ra_lines.purchase_order_date
                                                             || delimiter
                                                             || ra_lines.agreement_name
                                                             || delimiter
                                                             || ra_lines.memo_line_name
                                                             || delimiter
                                                             || ra_lines.document_number
                                                             || delimiter
                                                             || ra_lines.orig_system_batch_name
                                                             || delimiter
                                                             || ra_lines.link_to_line_context
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute1
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute2
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute3
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute4
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute5
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute6
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute7
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute8
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute9
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute10
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute11
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute12
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute13
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute14
                                                             || delimiter
                                                             || ra_lines.link_to_line_attribute15
                                                             || delimiter
                                                             || ra_lines.reference_line_context
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute1
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute2
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute3
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute4
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute5
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute6
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute7
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute8
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute9
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute10
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute11
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute12
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute13
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute14
                                                             || delimiter
                                                             || ra_lines.reference_line_attribute15
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_context
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute1
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute2
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute3
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute4
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute5
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute6
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute7
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute8
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute9
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute10
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute11
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute12
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute13
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute14
                                                             || delimiter
                                                             || ra_lines.link_to_parentline_attribute15
                                                             || delimiter
                                                             || ra_lines.receipt_method_name
                                                             || delimiter
                                                             || ra_lines.printing_option
                                                             || delimiter
                                                             || ra_lines.related_batch_source_name
                                                             || delimiter
                                                             || ra_lines.related_trx_number
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg1
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg2
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg3
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg4
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg5
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg6
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg7
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg8
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg9
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg10
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg11
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg12
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg13
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg14
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg15
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg16
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg17
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg18
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg19
                                                             || delimiter
                                                             || ra_lines.egp_system_items_seg20
                                                             || delimiter
                                                             || ra_lines.customer_bank_account_name
                                                             || delimiter
                                                             || ra_lines.reset_trx_date_flag
                                                             || delimiter
                                                             || ra_lines.payment_server_order_num
                                                             || delimiter
                                                             || ra_lines.last_trx_debit_auth_flag
                                                             || delimiter
                                                             || ra_lines.approval_code
                                                             || delimiter
                                                             || ra_lines.address_verification_code
                                                             || delimiter
                                                             || ra_lines.translated_description
                                                             || delimiter
                                                             || ra_lines.cons_billing_number
                                                             || delimiter
                                                             || ra_lines.promised_commitment_amount
                                                             || delimiter
                                                             || ra_lines.payment_set_id
                                                             || delimiter
                                                             || ra_lines.original_gl_date
                                                             || delimiter
                                                             || ra_lines.invoiced_line_acctg_level
                                                             || delimiter
                                                             || ra_lines.override_auto_accounting_flag
                                                             || delimiter
                                                             || ra_lines.historical_flag
                                                             || delimiter
                                                             || ra_lines.deferral_exclusion_flag
                                                             || delimiter
                                                             || ra_lines.payment_attributes
                                                             || delimiter
                                                             || ra_lines.billing_date
                                                             || delimiter
                                                             || ra_lines.attribute_category
                                                             || delimiter
                                                             || ra_lines.attribute1
                                                             || delimiter
                                                             || ra_lines.attribute2
                                                             || delimiter
                                                             || ra_lines.attribute3
                                                             || delimiter
                                                             || ra_lines.attribute4
                                                             || delimiter
                                                             || ra_lines.attribute5
                                                             || delimiter
                                                             || ra_lines.attribute6
                                                             || delimiter
                                                             || ra_lines.attribute7
                                                             || delimiter
                                                             || ra_lines.attribute8
                                                             || delimiter
                                                             || ra_lines.attribute9
                                                             || delimiter
                                                             || ra_lines.attribute10
                                                             || delimiter
                                                             || ra_lines.attribute11
                                                             || delimiter
                                                             || ra_lines.attribute12
                                                             || delimiter
                                                             || ra_lines.attribute13
                                                             || delimiter
                                                             || ra_lines.attribute14
                                                             || delimiter
                                                             || ra_lines.attribute15
                                                             || delimiter
                                                             || ra_lines.header_attribute_category
                                                             || delimiter
                                                             || ra_lines.header_attribute1
                                                             || delimiter
                                                             || ra_lines.header_attribute2
                                                             || delimiter
                                                             || ra_lines.header_attribute3
                                                             || delimiter
                                                             || ra_lines.header_attribute4
                                                             || delimiter
                                                             || ra_lines.header_attribute5
                                                             || delimiter
                                                             || ra_lines.header_attribute6
                                                             || delimiter
                                                             || ra_lines.header_attribute7
                                                             || delimiter
                                                             || ra_lines.header_attribute8
                                                             || delimiter
                                                             || ra_lines.header_attribute9
                                                             || delimiter
                                                             || ra_lines.header_attribute10
                                                             || delimiter
                                                             || ra_lines.header_attribute11
                                                             || delimiter
                                                             || ra_lines.header_attribute12
                                                             || delimiter
                                                             || ra_lines.header_attribute13
                                                             || delimiter
                                                             || ra_lines.header_attribute14
                                                             || delimiter
                                                             || ra_lines.header_attribute15
                                                             || delimiter
                                                             || ra_lines.header_gdf_attr_category
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute1
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute2
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute3
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute4
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute5
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute6
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute7
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute8
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute9
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute10
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute11
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute12
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute13
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute14
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute15
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute16
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute17
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute18
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute19
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute20
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute21
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute22
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute23
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute24
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute25
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute26
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute27
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute28
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute29
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute30
                                                             || delimiter
                                                             || ra_lines.line_gdf_attr_category
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute1
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute2
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute3
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute4
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute5
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute6
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute7
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute8
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute9
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute10
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute11
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute12
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute13
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute14
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute15
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute16
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute17
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute18
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute19
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute20
                                                             || delimiter
                                                             || ra_lines.bu_name
                                                             || delimiter
                                                             ||        ---Business unit Name
                                                              ra_lines.comments
                                                             || delimiter
                                                             || ra_lines.internal_notes
                                                             || delimiter
                                                             || ra_lines.cc_token_number
                                                             || delimiter
                                                             || ra_lines.cc_expiration_date
                                                             || delimiter
                                                             || ra_lines.cc_first_name
                                                             || delimiter
                                                             || ra_lines.cc_last_name
                                                             || delimiter
                                                             || ra_lines.cc_issuer_code
                                                             || delimiter
                                                             || ra_lines.cc_masked_number
                                                             || delimiter
                                                             || ra_lines.cc_auth_request_id
                                                             || delimiter
                                                             || ra_lines.cc_voice_auth_code
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number1
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number2
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number3
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number4
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number5
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number6
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number7
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number8
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number9
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number10
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number11
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_number12
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_date1
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_date2
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_date3
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_date4
                                                             || delimiter
                                                             || ra_lines.header_gdf_attribute_date5
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_number1
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_number2
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_number3
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_number4
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_number5
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_date1
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_date2
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_date3
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_date4
                                                             || delimiter
                                                             || ra_lines.line_gdf_attribute_date5
                                                             || delimiter
                                                             || ra_lines.freight_charge
                                                             || delimiter
                                                             || ra_lines.insurance_charge
                                                             || delimiter
                                                             || ra_lines.packing_charge
                                                             || delimiter
                                                             || ra_lines.miscellaneous_charge
                                                             || delimiter
                                                             || ra_lines.commercial_discount
                                                             || delimiter
                                                             || ra_lines.enf_seq_date_correlation_code
                                                             || delimiter
                                                             || ',,END'
                                                             || chr(13)
                                                             || chr(10));
        END LOOP;

	--        dbms_output.put_line(v_clob);
        RETURN v_clob;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'get_ra_interface_lines_csv_data', p_tracker =>
            'get_ra_interface_lines_csv_data', p_custom_err_info => 'EXCEPTION3 : get_ra_interface_lines_csv_data');
    END;

	/***************************************************************************
	*
	*  FUNCTION: GET_RA_INTERFACE_DISTRIBUTIONS_CSV_DATA
	*
	*  Description:  Used to write RA Interface Distributions to the CSV clob
	*
	**************************************************************************/

    FUNCTION get_ra_interface_distributions_csv_data (
        file_id_p NUMBER
    ) RETURN CLOB AS

        CURSOR ra_interface_distributions_cur IS
        SELECT
            *
        FROM
            xxagis_ra_interface_distributions_all
        WHERE
            file_id = file_id_p;

        delimiter VARCHAR2(1) := ',';
        v_clob    CLOB;
    BEGIN
        dbms_lob.createtemporary(v_clob, false, dbms_lob.call);
        dbms_lob.open(v_clob, dbms_lob.lob_readwrite);

	-- write RA Interface Distributions to the CSV clob
        FOR ra_distributions IN ra_interface_distributions_cur LOOP
            dbms_lob.writeappend(v_clob, length(delimiter
                                                || ra_distributions.account_class
                                                || delimiter
                                                || to_char(ra_distributions.amount, 'fm999999999999.90')
                                                || delimiter
                                                || to_char(ra_distributions.percent, 'fm999999999999.90')
                                                || delimiter
                                                || ra_distributions.acctd_amount
                                                || delimiter
                                                || ra_distributions.interface_line_context
                                                || delimiter
                                                || ra_distributions.interface_line_attribute1
                                                || delimiter
                                                || ra_distributions.interface_line_attribute2
                                                || delimiter
                                                || ra_distributions.interface_line_attribute3
                                                || delimiter
                                                || ra_distributions.interface_line_attribute4
                                                || delimiter
                                                || ra_distributions.interface_line_attribute5
                                                || delimiter
                                                || ra_distributions.interface_line_attribute6
                                                || delimiter
                                                || ra_distributions.interface_line_attribute7
                                                || delimiter
                                                || ra_distributions.interface_line_attribute8
                                                || delimiter
                                                || ra_distributions.interface_line_attribute9
                                                || delimiter
                                                || ra_distributions.interface_line_attribute10
                                                || delimiter
                                                || ra_distributions.interface_line_attribute11
                                                || delimiter
                                                || ra_distributions.interface_line_attribute12
                                                || delimiter
                                                || ra_distributions.interface_line_attribute13
                                                || delimiter
                                                || ra_distributions.interface_line_attribute14
                                                || delimiter
                                                || ra_distributions.interface_line_attribute15
                                                || delimiter
                                                || ra_distributions.segment1
                                                || delimiter
                                                || ra_distributions.segment2
                                                || delimiter
                                                || ra_distributions.segment3
                                                || delimiter
                                                || ra_distributions.segment4
                                                || delimiter
                                                || ra_distributions.segment5
                                                || delimiter
                                                || ra_distributions.segment6
                                                || delimiter
                                                || ra_distributions.segment7
                                                || delimiter
                                                || ra_distributions.segment8
                                                || delimiter
                                                || ra_distributions.segment9
                                                || delimiter
                                                || ra_distributions.segment10
                                                || delimiter
                                                || ra_distributions.segment11
                                                || delimiter
                                                || ra_distributions.segment12
                                                || delimiter
                                                || ra_distributions.segment13
                                                || delimiter
                                                || ra_distributions.segment14
                                                || delimiter
                                                || ra_distributions.segment15
                                                || delimiter
                                                || ra_distributions.segment16
                                                || delimiter
                                                || ra_distributions.segment17
                                                || delimiter
                                                || ra_distributions.segment18
                                                || delimiter
                                                || ra_distributions.segment19
                                                || delimiter
                                                || ra_distributions.segment20
                                                || delimiter
                                                || ra_distributions.segment21
                                                || delimiter
                                                || ra_distributions.segment22
                                                || delimiter
                                                || ra_distributions.segment23
                                                || delimiter
                                                || ra_distributions.segment24
                                                || delimiter
                                                || ra_distributions.segment25
                                                || delimiter
                                                || ra_distributions.segment26
                                                || delimiter
                                                || ra_distributions.segment27
                                                || delimiter
                                                || ra_distributions.segment28
                                                || delimiter
                                                || ra_distributions.segment29
                                                || delimiter
                                                || ra_distributions.segment30
                                                || delimiter
                                                || ra_distributions.comments
                                                || delimiter
                                                || ra_distributions.interim_tax_segment1
                                                || delimiter
                                                || ra_distributions.interim_tax_segment2
                                                || delimiter
                                                || ra_distributions.interim_tax_segment3
                                                || delimiter
                                                || ra_distributions.interim_tax_segment4
                                                || delimiter
                                                || ra_distributions.interim_tax_segment5
                                                || delimiter
                                                || ra_distributions.interim_tax_segment6
                                                || delimiter
                                                || ra_distributions.interim_tax_segment7
                                                || delimiter
                                                || ra_distributions.interim_tax_segment8
                                                || delimiter
                                                || ra_distributions.interim_tax_segment9
                                                || delimiter
                                                || ra_distributions.interim_tax_segment10
                                                || delimiter
                                                || ra_distributions.interim_tax_segment11
                                                || delimiter
                                                || ra_distributions.interim_tax_segment12
                                                || delimiter
                                                || ra_distributions.interim_tax_segment13
                                                || delimiter
                                                || ra_distributions.interim_tax_segment14
                                                || delimiter
                                                || ra_distributions.interim_tax_segment15
                                                || delimiter
                                                || ra_distributions.interim_tax_segment16
                                                || delimiter
                                                || ra_distributions.interim_tax_segment17
                                                || delimiter
                                                || ra_distributions.interim_tax_segment18
                                                || delimiter
                                                || ra_distributions.interim_tax_segment19
                                                || delimiter
                                                || ra_distributions.interim_tax_segment20
                                                || delimiter
                                                || ra_distributions.interim_tax_segment21
                                                || delimiter
                                                || ra_distributions.interim_tax_segment22
                                                || delimiter
                                                || ra_distributions.interim_tax_segment23
                                                || delimiter
                                                || ra_distributions.interim_tax_segment24
                                                || delimiter
                                                || ra_distributions.interim_tax_segment25
                                                || delimiter
                                                || ra_distributions.interim_tax_segment26
                                                || delimiter
                                                || ra_distributions.interim_tax_segment27
                                                || delimiter
                                                || ra_distributions.interim_tax_segment28
                                                || delimiter
                                                || ra_distributions.interim_tax_segment29
                                                || delimiter
                                                || ra_distributions.interim_tax_segment30
                                                || delimiter
                                                || ra_distributions.attribute_category
                                                || delimiter
                                                || ra_distributions.attribute1
                                                || delimiter
                                                || ra_distributions.attribute2
                                                || delimiter
                                                || ra_distributions.attribute3
                                                || delimiter
                                                || ra_distributions.attribute4
                                                || delimiter
                                                || ra_distributions.attribute5
                                                || delimiter
                                                || ra_distributions.attribute6
                                                || delimiter
                                                || ra_distributions.attribute7
                                                || delimiter
                                                || ra_distributions.attribute8
                                                || delimiter
                                                || ra_distributions.attribute9
                                                || delimiter
                                                || ra_distributions.attribute10
                                                || delimiter
                                                || ra_distributions.attribute11
                                                || delimiter
                                                || ra_distributions.attribute12
                                                || delimiter
                                                || ra_distributions.attribute13
                                                || delimiter
                                                || ra_distributions.attribute14
                                                || delimiter
                                                || ra_distributions.attribute15
                                                || delimiter
                                                || ra_distributions.bu_name
                                                || delimiter
                                                ||                     ---Business unit Name
                                                 'END'
                                                || chr(13)
                                                || chr(10)), delimiter
                                                             || ra_distributions.account_class
                                                             || delimiter
                                                             || to_char(ra_distributions.amount, 'fm999999999999.90')
                                                             || delimiter
                                                             || to_char(ra_distributions.percent, 'fm999999999999.90')
                                                             || delimiter
                                                             || ra_distributions.acctd_amount
                                                             || delimiter
                                                             || ra_distributions.interface_line_context
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute1
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute2
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute3
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute4
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute5
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute6
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute7
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute8
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute9
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute10
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute11
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute12
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute13
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute14
                                                             || delimiter
                                                             || ra_distributions.interface_line_attribute15
                                                             || delimiter
                                                             || ra_distributions.segment1
                                                             || delimiter
                                                             || ra_distributions.segment2
                                                             || delimiter
                                                             || ra_distributions.segment3
                                                             || delimiter
                                                             || ra_distributions.segment4
                                                             || delimiter
                                                             || ra_distributions.segment5
                                                             || delimiter
                                                             || ra_distributions.segment6
                                                             || delimiter
                                                             || ra_distributions.segment7
                                                             || delimiter
                                                             || ra_distributions.segment8
                                                             || delimiter
                                                             || ra_distributions.segment9
                                                             || delimiter
                                                             || ra_distributions.segment10
                                                             || delimiter
                                                             || ra_distributions.segment11
                                                             || delimiter
                                                             || ra_distributions.segment12
                                                             || delimiter
                                                             || ra_distributions.segment13
                                                             || delimiter
                                                             || ra_distributions.segment14
                                                             || delimiter
                                                             || ra_distributions.segment15
                                                             || delimiter
                                                             || ra_distributions.segment16
                                                             || delimiter
                                                             || ra_distributions.segment17
                                                             || delimiter
                                                             || ra_distributions.segment18
                                                             || delimiter
                                                             || ra_distributions.segment19
                                                             || delimiter
                                                             || ra_distributions.segment20
                                                             || delimiter
                                                             || ra_distributions.segment21
                                                             || delimiter
                                                             || ra_distributions.segment22
                                                             || delimiter
                                                             || ra_distributions.segment23
                                                             || delimiter
                                                             || ra_distributions.segment24
                                                             || delimiter
                                                             || ra_distributions.segment25
                                                             || delimiter
                                                             || ra_distributions.segment26
                                                             || delimiter
                                                             || ra_distributions.segment27
                                                             || delimiter
                                                             || ra_distributions.segment28
                                                             || delimiter
                                                             || ra_distributions.segment29
                                                             || delimiter
                                                             || ra_distributions.segment30
                                                             || delimiter
                                                             || ra_distributions.comments
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment1
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment2
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment3
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment4
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment5
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment6
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment7
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment8
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment9
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment10
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment11
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment12
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment13
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment14
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment15
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment16
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment17
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment18
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment19
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment20
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment21
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment22
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment23
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment24
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment25
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment26
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment27
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment28
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment29
                                                             || delimiter
                                                             || ra_distributions.interim_tax_segment30
                                                             || delimiter
                                                             || ra_distributions.attribute_category
                                                             || delimiter
                                                             || ra_distributions.attribute1
                                                             || delimiter
                                                             || ra_distributions.attribute2
                                                             || delimiter
                                                             || ra_distributions.attribute3
                                                             || delimiter
                                                             || ra_distributions.attribute4
                                                             || delimiter
                                                             || ra_distributions.attribute5
                                                             || delimiter
                                                             || ra_distributions.attribute6
                                                             || delimiter
                                                             || ra_distributions.attribute7
                                                             || delimiter
                                                             || ra_distributions.attribute8
                                                             || delimiter
                                                             || ra_distributions.attribute9
                                                             || delimiter
                                                             || ra_distributions.attribute10
                                                             || delimiter
                                                             || ra_distributions.attribute11
                                                             || delimiter
                                                             || ra_distributions.attribute12
                                                             || delimiter
                                                             || ra_distributions.attribute13
                                                             || delimiter
                                                             || ra_distributions.attribute14
                                                             || delimiter
                                                             || ra_distributions.attribute15
                                                             || delimiter
                                                             || ra_distributions.bu_name
                                                             || delimiter
                                                             ||                     ---Business unit Name
                                                              'END'
                                                             || chr(13)
                                                             || chr(10));
        END LOOP;

			--dbms_output.put_line(v_clob);
        RETURN v_clob;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'get_ra_interface_distributions_csv_data',
            p_tracker => 'get_ra_interface_distributions_csv_data', p_custom_err_info => 'EXCEPTION3 : get_ra_interface_distributions_csv_data');
    END;

    PROCEDURE trigger_oic_process (
        file_id_p NUMBER,
	/*CEN-8274_2 Start*/
		file_source_p VARCHAR2 DEFAULT NULL,
		count_p NUMBER DEFAULT 0
	/*CEN-8274_2 End*/
    ) IS

        CURSOR xx_get_conn_details_cur (
            p_username VARCHAR2
        ) IS
        SELECT
            *
        FROM
            xxagis_soap_connection_details
        WHERE
            source = 'OIC';

        CURSOR ar_batches IS
        SELECT
            xrl.bu_name,
            xrl.batch_source_name,
            pbu.business_unit_id
        FROM
            xxagis_ra_interface_lines_all xrl,
            pbs_business_unit             pbu
        WHERE
                file_id = file_id_p
            AND xrl.bu_name LIKE pbu.business_unit
        GROUP BY
            xrl.bu_name,
            xrl.batch_source_name,
            pbu.business_unit_id;

        l_count                 NUMBER;
        l_source_name           VARCHAR2(100);
        xx_get_conn_details_rec xx_get_conn_details_cur%rowtype;
        l_envelope              CLOB;
        l_xml                   XMLTYPE;
		--l_xml VARCHAR2(500);
        l_result                VARCHAR2(32767);
        l_http_request          utl_http.req;
        l_http_response         utl_http.resp;
        l_url                   VARCHAR2(1000);
        l_username              VARCHAR2(100);
        l_password              VARCHAR2(100);
        l_wallet_path           VARCHAR2(1000);
        l_wallet_password       VARCHAR2(100);
        l_proxy                 VARCHAR2(100);
        l_action                VARCHAR2(100);
        l_process               VARCHAR2(1000);
        l_path                  VARCHAR2(100);
	/*CEN-8274_2 Start*/
		V_AR_STATUS				VARCHAR2(100);
		V_AGIS_STATUS           VARCHAR2(100);
		V_ERROR_MESSAGE			VARCHAR2(4000);
		V_MESSAGE               VARCHAR2(4000);
		V_COUNT                 NUMBER;
	/*CEN-8274_2 End*/

    BEGIN
        writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'BEGIN', 'OPEN xx_get_conn_details_cur'); -- 3-26961848861/2706282391

        OPEN xx_get_conn_details_cur(gc_user); --p_username
			-- Fetch connection details to variables
        FETCH xx_get_conn_details_cur INTO xx_get_conn_details_rec;
        l_url := xx_get_conn_details_rec.url;
        l_username := xx_get_conn_details_rec.username;
        l_password := xx_get_conn_details_rec.password;
        l_wallet_path := xx_get_conn_details_rec.wallet_path;
        l_wallet_password := xx_get_conn_details_rec.wallet_password;
        l_proxy := xx_get_conn_details_rec.proxy_details;
        l_action := xx_get_conn_details_rec.action;
				  -- close cursor
        CLOSE xx_get_conn_details_cur;
        dbms_output.put_line('l_url: ' || l_url);
        dbms_output.put_line('l_username: ' || l_username);
        dbms_output.put_line('l_password: ' || l_password);
        dbms_output.put_line('l_wallet_path: ' || l_wallet_path);
        dbms_output.put_line('l_wallet_password: ' || l_wallet_password);
        dbms_output.put_line('l_proxy: ' || l_proxy);
        dbms_output.put_line('l_action: ' || l_action);

	/*CEN-8274_2 Start*/
		IF (file_source_p = 'AGIS' OR file_source_p IS NULL) THEN
	/*CEN-8274_2 End*/

        SELECT
            COUNT(*)
        INTO l_count
        FROM
            xxagis_agis_stage
        WHERE
            file_id = file_id_p;

        IF ( l_count > 0 ) THEN

            writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'l_count ' || l_count, 'SOAP ENVELOPE '); -- 3-26961848861/2706282391

            l_envelope := '<soapenv:Envelope xmlns:imp="http://www.oldmutual.co.za/agis/import" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
				   <soapenv:Header>
					  <wsse:Security soapenv:mustUnderstand="1" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
						 <wsse:UsernameToken>
							<wsse:Username>'
                          || l_username
                          || '</wsse:Username>
							<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">'
                          || l_password
                          || '</wsse:Password>
						 </wsse:UsernameToken>
					  </wsse:Security>
				   </soapenv:Header>
				   <soapenv:Body>
					   <imp:AGISRequest>
						 <imp:Request>
							<imp:SourceId>AGIS</imp:SourceId>
							<imp:FileId>'
                          || file_id_p
                          || '</imp:FileId>
						 </imp:Request>
					  </imp:AGISRequest>
				   </soapenv:Body>
				</soapenv:Envelope>';

            IF ( l_proxy IS NOT NULL ) THEN
                utl_http.set_proxy(l_proxy);
            END IF;
            BEGIN
				  /* 3-26961848861/2706282391 START */
                writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'l_count '
                                                                                                   || l_count
                                                                                                   || 'l_envelope = '
                                                                                                   || l_envelope, 'SOAP ENVELOPE'); -- 3-26961848861/2706282391
                BEGIN
                    FOR nls_data IN (
                        SELECT
                            sys_context('USERENV', 'LANGUAGE')          session_lang,
                            sys_context('USERENV', 'NLS_DATE_FORMAT')   session_date_format,
                            sys_context('USERENV', 'NLS_DATE_LANGUAGE') session_date_lang,
                            sys_context('USERENV', 'NLS_TERRITORY')     session_terr
                        FROM
                            dual
                    ) LOOP
                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session language ' || nls_data.
                        session_lang, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session date format ' || nls_data.
                        session_date_format, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session date lang ' || nls_data.
                        session_date_lang, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session territoty ' || nls_data.
                        session_terr, 'L_PROCESS_ACTION');

                    END LOOP;
					  --
                    apex_web_service.g_request_headers.DELETE();
                    apex_web_service.g_request_headers(1).name := 'Content-Type';
                    apex_web_service.g_request_headers(1).value := 'application/xml';
                    writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'AFTER Content-Type', 'L_PROCESS_ACTION');
					   /* 3-26961848861/2706282391 END */
					  --
                    l_xml := apex_web_service.make_request(p_url => l_url, p_envelope => l_envelope, p_action => l_action, p_wallet_path =>
                    l_wallet_path, p_wallet_pwd => l_wallet_password);

                    writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'l_xml ' || l_xml.getstringval(),
                    'SOAP ENVELOPE '); -- 3-26961848861/2706282391

	/*CEN-8274_2 Start*/
			DBMS_SESSION.SLEEP(10);

			IF upper(l_xml.getstringval()) like upper('%<sqlerrm><![CDATA[ORA-31011: XML parsing failed]]></sqlerrm>%')
			THEN

			BEGIN

			SELECT NVL(TRIM(SUBSTR(l_xml.getstringval(),INSTR(l_xml.getstringval(),'<TITLE>')+LENGTH('<TITLE>'),
				   (INSTR(l_xml.getstringval(),'</TITLE>'))-(INSTR(l_xml.getstringval(),'<TITLE>')+LENGTH('<TITLE>')))||' '||
				   SUBSTR(l_xml.getstringval(),INSTR(l_xml.getstringval(),'<b>')+LENGTH('<b>'),
				   (INSTR(l_xml.getstringval(),'</b>'))-(INSTR(l_xml.getstringval(),'<b>')+LENGTH('<b>'))
                   )),
				   'There are no currently active integrations.')
              INTO v_error_message
              FROM dual;

			EXCEPTION
			WHEN OTHERS THEN
			v_error_message := NULL;

			END;

			IF count_p = 0 THEN

			UPDATE xxagis_file_header
			   SET file_interface_status = gc_oic_not_reachable,
			       file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p
               AND (file_interface_status<>'ERROR' OR file_interface_status IS NULL);

			v_message:='Trigger_OIC_Process failed to connect to OIC. '|| CHR(13) ||'Error: ' ||v_error_message;

			ELSIF count_p > 0 AND count_p < 3 THEN

			UPDATE xxagis_file_header
			   SET file_interface_status = gc_oic_not_reachable,
			       file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p
               AND (file_interface_status<>'ERROR' OR file_interface_status IS NULL);

			v_message := 'Number of attempt made to reprocess the file: '||count_p||'. But the connection to OIC was not made.' || CHR(13) ||'ERROR: '|| v_error_message;

			ELSE

			UPDATE xxagis_file_header
			   SET file_interface_status = 'ERROR',
                   file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p;

			BEGIN

		       SELECT ar_load_request_id,agis_load_request_id
		         INTO v_ar_status,v_agis_status
		         FROM xxagis_file_header
			    WHERE file_id = file_id_p;

		        EXCEPTION
		        WHEN OTHERS THEN
		              v_agis_status := NULL;
		              v_ar_status := NULL;

		   END;

		   IF v_agis_status IS NOT NULL and v_ar_status IS NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'AR lines for file_id-'||file_id_p||' did not get transferred to OIC servers. The AR data will need to be reloaded. Please log a call with FinCoE so that they can assist with data identification.';
		   ELSIF v_agis_status IS NULL and v_ar_status IS NOT NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'AGIS lines for file_id-'||file_id_p||' did not get transferred to OIC servers. The AGIS data will need to be reloaded. Please log a call with FinCoE so that they can assist with data identification.';
		   ELSIF v_agis_status IS NULL and v_ar_status IS NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'The file_id-'||file_id_p||' did not get transferred to OIC servers. Please re upload the file and process.';

		   END IF;

		   v_message:= 'Number of attempt made to reprocess the file: 3. But the connection to OIC was not made. '|| CHR(13 )||'ERROR: '|| v_error_message;

			END IF;

			END IF;
	/*CEN-8274_2 End*/

                EXCEPTION
                    WHEN OTHERS THEN
                        dbms_output.put_line('Error at apex_web_service.make_request' || sqlerrm);
                        writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'EXCEPTION1 Error at apex_web_service.make_request ',
                        'sqlerrm ' || sqlerrm); -- 3-26961848861/2706282391
                        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'trigger_oic_process', p_tracker =>
                        'file_id_p ' || file_id_p, p_custom_err_info => 'EXCEPTION1 Error at apex_web_service.make_request '); -- -- 3-26961848861/2706282391
                END;

            END;

        END IF;

	/*CEN-8274_2 Start*/
		END IF;

		IF (file_source_p = 'AR' OR file_source_p IS NULL) THEN 
	/*CEN-8274_2 End*/ 

        FOR rec IN ar_batches LOOP
            writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'AR file_id_p ' || file_id_p, 'AR_BATCHES', 'SOAP ENVELOPE'); -- 3-26961848861/2706282391
				--
            l_envelope := '<soapenv:Envelope xmlns:imp="http://www.oldmutual.co.za/agis/import" xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/">
				   <soapenv:Header>
					  <wsse:Security soapenv:mustUnderstand="1" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
						 <wsse:UsernameToken>
							<wsse:Username>'
                          || l_username
                          || '</wsse:Username>
							<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">'
                          || l_password
                          || '</wsse:Password>
						 </wsse:UsernameToken>
					  </wsse:Security>
				   </soapenv:Header>
				   <soapenv:Body>
					   <imp:AGISRequest>
						 <imp:Request>
							<imp:SourceId>AR</imp:SourceId>
							<imp:FileId>'
                          || file_id_p
                          || '</imp:FileId>
							<imp:TransactionSource>'
                          || rec.batch_source_name
                          || '</imp:TransactionSource>
							<imp:BusinessUnitID>'
                          || rec.business_unit_id
                          || '</imp:BusinessUnitID>
						 </imp:Request>
					  </imp:AGISRequest>
				   </soapenv:Body>
				</soapenv:Envelope>';

            IF ( l_proxy IS NOT NULL ) THEN
                utl_http.set_proxy(l_proxy);
            END IF;
            writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'AR file_id_p ' || file_id_p, 'l_envelope = ' || l_envelope, 'SOAP ENVELOPE '); -- 3-26961848861/2706282391
            BEGIN
	--                dbms_output.put_line('l_envelope: ' || l_envelope);
					/* 3-26961848861/2706282391 START*/
                BEGIN
                    FOR nls_data IN (
                        SELECT
                            sys_context('USERENV', 'LANGUAGE')          session_lang,
                            sys_context('USERENV', 'NLS_DATE_FORMAT')   session_date_format,
                            sys_context('USERENV', 'NLS_DATE_LANGUAGE') session_date_lang,
                            sys_context('USERENV', 'NLS_TERRITORY')     session_terr
                        FROM
                            dual
                    ) LOOP
                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session language ' || nls_data.
                        session_lang, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session date format ' || nls_data.
                        session_date_format, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session date lang ' || nls_data.
                        session_date_lang, 'L_PROCESS_ACTION');

                        writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'session territoty ' || nls_data.
                        session_terr, 'L_PROCESS_ACTION');

                    END LOOP;
                END;

                apex_web_service.g_request_headers.DELETE();
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/xml';
                writetolog('xxahcs_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'AFTER AR Content-Type', 'L_PROCESS_ACTION');
					 --  /* 3-26961848861/2706282391 END     Animesh
					--
                l_xml := apex_web_service.make_request(p_url => l_url, p_envelope => l_envelope, p_action => l_action, p_wallet_path =>
                l_wallet_path, p_wallet_pwd => l_wallet_password);

                writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'AR file_id_p ' || file_id_p, 'l_xml ' || l_xml.getstringval(),
                'AR_BATCHES '); -- 3-26961848861/2706282391

	/*CEN-8274_2 Start*/

			DBMS_SESSION.SLEEP(10);

			IF upper(l_xml.getstringval()) like upper('%<sqlerrm><![CDATA[ORA-31011: XML parsing failed]]></sqlerrm>%')
			THEN

			BEGIN

			SELECT NVL(TRIM(SUBSTR(l_xml.getstringval(),INSTR(l_xml.getstringval(),'<TITLE>')+LENGTH('<TITLE>'),
				   (INSTR(l_xml.getstringval(),'</TITLE>'))-(INSTR(l_xml.getstringval(),'<TITLE>')+LENGTH('<TITLE>')))||' '||
				   SUBSTR(l_xml.getstringval(),INSTR(l_xml.getstringval(),'<b>')+LENGTH('<b>'),
				   (INSTR(l_xml.getstringval(),'</b>'))-(INSTR(l_xml.getstringval(),'<b>')+LENGTH('<b>'))
                   )),
				   'There are no currently active integrations.')
              INTO v_error_message
              FROM dual;

			EXCEPTION
			WHEN OTHERS THEN
			v_error_message := NULL;

			END;

			IF count_p = 0 THEN

			UPDATE xxagis_file_header
			   SET file_interface_status = gc_oic_not_reachable,
			       file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p
               AND (file_interface_status<>'ERROR' OR file_interface_status IS NULL);

			v_message:='Trigger_OIC_Process failed to connect to OIC. '|| CHR(13) ||'Error: ' ||v_error_message;

			ELSIF count_p > 0 AND count_p < 3 THEN

			UPDATE xxagis_file_header
			   SET file_interface_status = gc_oic_not_reachable,
			       file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p
               AND (file_interface_status<>'ERROR' OR file_interface_status IS NULL);

			v_message := 'Number of attempt made to reprocess the file: '||count_p||'. But the connection to OIC was not made.' || CHR(13) ||'ERROR: '|| v_error_message;

			ELSE

			UPDATE xxagis_file_header
			   SET file_interface_status = 'ERROR',
                   file_load_status = 'ERROR',
				   last_update_date = SYSDATE
			 WHERE file_id = file_id_p;

			BEGIN

		       SELECT ar_load_request_id,agis_load_request_id
		         INTO v_ar_status,v_agis_status
		         FROM xxagis_file_header
			    WHERE file_id = file_id_p;

		        EXCEPTION
		        WHEN OTHERS THEN
		              v_agis_status := NULL;
		              v_ar_status := NULL;

		   END;

		   IF v_agis_status IS NOT NULL and v_ar_status IS NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'AR lines for file_id-'||file_id_p||' did not get transferred to OIC servers. The AR data will need to be reloaded. Please log a call with FinCoE so that they can assist with data identification.';
		   ELSIF v_agis_status IS NULL and v_ar_status IS NOT NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'AGIS lines for file_id-'||file_id_p||' did not get transferred to OIC servers. The AGIS data will need to be reloaded. Please log a call with FinCoE so that they can assist with data identification.';
		   ELSIF v_agis_status IS NULL and v_ar_status IS NULL THEN
		   v_error_message := v_error_message || CHR(13) || CHR(13) ||'The file_id-'||file_id_p||' did not get transferred to OIC servers. Please re upload the file and process.';

		   END IF;

		   v_message:= 'Number of attempt made to reprocess the file: 3. But the file still was unable to process due to below issue. '|| CHR(13 )||'ERROR: '|| v_error_message;


			END IF;

			END IF;
	/*CEN-8274_2 End*/

            EXCEPTION
                WHEN OTHERS THEN
                    dbms_output.put_line('Error at apex_web_service.make_request' || sqlerrm);
                    writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'AR file_id_p ' || file_id_p, 'EXCEPTION2 Error at apex_web_service.make_request ',
                    'sqlerrm ' || sqlerrm); -- 3-26961848861/2706282391
                    oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'trigger_oic_process', p_tracker =>
                    'file_id_p ' || file_id_p, p_custom_err_info => 'EXCEPTION1 Error at apex_web_service.make_request '); -- 3-26961848861/2706282391

            END;

        END LOOP;

	/*CEN-8274_2 Start*/
		END IF;  

		IF count_p < 3 THEN

		   UPDATE xxagis_file_header
			   SET error_message =  error_message|| CHR(13)|| CHR(13) || v_message
			 WHERE file_id = file_id_p
			   AND file_interface_status = gc_oic_not_reachable;

		   COMMIT;

		ELSE

			UPDATE xxagis_file_header
			   SET error_message = error_message || CHR(13) || CHR(13) ||v_message
			 WHERE file_id = file_id_p
			   AND file_interface_status = 'ERROR';

		END IF;

		IF (v_error_message IS NULL AND count_p > 0) THEN

		BEGIN 
		   SELECT SUBSTR(error_details,INSTR(error_details,'<err:title>')+LENGTH('<err:title>'),
			     (INSTR(error_details,'</err:title>'))-(INSTR(error_details,'<err:title>')+LENGTH('<err:title>')))||' '||
                  SUBSTR(error_details,INSTR(error_details,'<err:detail>')+LENGTH('<err:detail>'),
                 (INSTR(error_details,'</err:detail>'))-(INSTR(error_details,'<err:detail>')+LENGTH('<err:detail>'))),
                 count(*)
			 INTO v_error_message,v_count
			 FROM xxagis_oic_file_prcs_details
			WHERE file_id = file_id_p
		      AND file_source in ('AGIS_ERR_'||count_p,'AR_ERR_'||count_p)
			  AND error_details IS NOT NULL
         GROUP BY error_details;

		   EXCEPTION
		   WHEN OTHERS THEN
		   v_error_message := NULL;
           v_count := 0;
		END;

       IF v_count > 0 THEN

		UPDATE xxagis_file_header
		   SET error_message = error_message || CHR(13) ||'The file was not uploaded successfully due to error. '|| CHR(13) ||'Error: '||v_error_message|| CHR(13) ||'Hence attempt: '||count_p||' was made to reprocess the file.',
		   last_update_date = sysdate
		 WHERE file_id = file_id_p;

        END IF;
        END IF;
	/*CEN-8274_2 End*/

		COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            dbms_output.put_line('Error while inserting converted values to table'
                                 || 'file_id_p '
                                 || file_id_p
                                 || ' '
                                 || sqlerrm);

            writetolog('xxagis_utility_pkg', 'trigger_oic_process', 'file_id_p ' || file_id_p, 'Exception3 Error while inserting converted values to table',
            'sqlerrm ' || sqlerrm); -- 3-26961848861/2706282391
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'trigger_oic_process', p_tracker =>
            'file_id_p ' || file_id_p, p_custom_err_info => 'EXCEPTION1 Error at apex_web_service.make_request '); -- -- 3-26961848861/2706282391


    END;

	/*CEN-8274_1 Start*/
    /***************************************************************************
	*
	*  PROCEDURE: RETRIGGER_OIC_PROCESS
	*
	*  Description:  This procedure is to fetch files which needs to be reprocessed
	*
	**************************************************************************/

	PROCEDURE retrigger_oic_process IS

	CURSOR xx_tran_file_trigger
		  IS
		SELECT file_id,ar_load_request_id,agis_load_request_id
		  FROM xxagis_file_header
		 WHERE 1=1
		   AND file_status='SUCCESS'
		   AND (file_interface_status = gc_oic_not_reachable
	        OR (file_interface_status IS NULL AND last_update_date > (sysdate-2)))
		   AND (ar_load_request_id IS NULL
			OR agis_load_request_id IS NULL)
		   AND (file_load_status='ERROR' 
            OR ar_file_load_status <> 'SUCCEEDED'); 

        v_count                 NUMBER := 0;
		v_upd_source			VARCHAR2(20);
        v_error_count           NUMBER := 0;
        v_source                VARCHAR2(20);
		v_agis_count            NUMBER := 0;
		v_ar_count              NUMBER := 0;
		v_file_source_count     NUMBER := 0;

    BEGIN

		FOR cur_rec IN xx_tran_file_trigger LOOP

		UPDATE xxagis_file_header
		SET reprocess_attempt = reprocess_attempt + 1
		WHERE file_id = cur_rec.file_id;

		--To check the count for file_source of the file
		SELECT COUNT(*)
          INTO v_agis_count
          FROM xxagis_agis_stage
         WHERE file_id = cur_rec.file_id;

        SELECT COUNT(*)
          INTO v_ar_count
          FROM xxagis_ar_stage
         WHERE file_id = cur_rec.file_id;

		--To check whether file has patially or completely failed the transfer
	    IF v_ar_count > 0 AND v_agis_count = 0 AND cur_rec.ar_load_request_id IS NULL THEN
		     v_source := 'AR';
		ELSIF v_ar_count = 0 AND v_agis_count > 0 AND cur_rec.agis_load_request_id IS NULL THEN
			 v_source := 'AGIS';
		ELSIF v_ar_count > 0 AND v_agis_count > 0 THEN

		  IF cur_rec.agis_load_request_id IS NULL AND cur_rec.ar_load_request_id IS NOT NULL THEN
		     v_source := 'AGIS';
		  ELSIF cur_rec.ar_load_request_id IS NULL AND cur_rec.agis_load_request_id IS NOT NULL THEN
		     v_source := 'AR';
		  ELSE
		     v_source := NULL;
		  END IF;

		END IF;

        --Check the record of the file in the table  
        BEGIN
          SELECT COUNT(*)
            INTO v_error_count
            FROM xxagis_oic_file_prcs_details
           WHERE file_id = cur_rec.file_id
		     AND file_source = NVL(v_source,file_source);

           EXCEPTION
           WHEN OTHERS THEN
           v_error_count := 0;
        END;

		--If the file did not reach OIC and record not exist in OIC PRCS DETAIL table   
        IF v_error_count = 0 THEN      

           BEGIN

				SELECT reprocess_attempt
				  INTO v_count
				  FROM xxagis_file_header
				 WHERE file_id = cur_rec.file_id;

				EXCEPTION
				WHEN OTHERS THEN
					   v_count := 0;
		   END;

	   ELSE
		--If file has failed the transfer partially
		IF (v_source = 'AGIS' OR v_source = 'AR') THEN

           SELECT COUNT(*) 
			 INTO v_count
             FROM xxagis_oic_file_prcs_details 
            WHERE file_id = cur_rec.file_id
			  AND file_source LIKE v_source||'%';

		  IF (v_count < 4) THEN

		  v_upd_source := '_ERR_'||v_count;

            UPDATE xxagis_oic_file_prcs_details
			   SET file_source = v_source||v_upd_source
             WHERE FILE_ID = cur_rec.file_id
			   AND file_source = v_source;

		  END IF;	  

		--If the file transfer has failed completely   
		ELSE

		   SELECT COUNT(*) 
			 INTO v_count
             FROM xxagis_oic_file_prcs_details 
            WHERE file_id = cur_rec.file_id
			  AND file_source like 'AR%'
	     GROUP BY file_id;

		IF (v_count < 4) THEN

		  v_upd_source := '_ERR_'||v_count;

            UPDATE xxagis_oic_file_prcs_details
			   SET file_source = file_source||v_upd_source
             WHERE FILE_ID = cur_rec.file_id
			   AND file_source IN ('AGIS','AR');

		END IF;	

		END IF;   

		COMMIT;
		END IF;

			--Procedure is called to reprocess the failed file
			trigger_oic_process(cur_rec.file_id,v_source,v_count);

	    END LOOP;

	END;

    /*CEN-8274_1 End*/

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_ACCOUNT_INSERT_UPDATE
	*
	*  Description:  Syncs Customer Account BIP Report into XXAGIS_CUSTOMER_ACCOUNT table
	*
	**************************************************************************/

    PROCEDURE agis_customer_account_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            cust_account_id          xxagis_customer_account.cust_account_id%TYPE,
            account_number           xxagis_customer_account.account_number%TYPE,
            creation_date            xxagis_customer_account.creation_date%TYPE,
            account_name             xxagis_customer_account.account_name%TYPE,
            last_update_date         xxagis_customer_account.last_update_date%TYPE,
            attribute3               xxagis_customer_account.attribute3%TYPE,
            status                   xxagis_customer_account.status%TYPE,
            account_termination_date xxagis_customer_account.account_termination_date%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_customer_account_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_ACCOUNT',
        'AGIS_CUSTOMER_ACCOUNT');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.CUST_ACCOUNT_ID
				,x.ACCOUNT_NUMBER
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.ACCOUNT_NAME
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,ATTRIBUTE3
				,STATUS
				,TO_CHAR(TO_DATE(SUBSTR(x.ACCOUNT_TERMINATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  CUST_ACCOUNT_ID NUMBER PATH ''./CUST_ACCOUNT_ID''
										  ,ACCOUNT_NUMBER VARCHAR2(240) PATH ''./ACCOUNT_NUMBER''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,ACCOUNT_NAME VARCHAR2(300) PATH ''./ACCOUNT_NAME''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,ATTRIBUTE3 VARCHAR2(150) PATH ''./ATTRIBUTE3''
										  ,STATUS VARCHAR2(150) PATH ''./STATUS''
										  ,ACCOUNT_TERMINATION_DATE VARCHAR2(150) PATH ''./ACCOUNT_TERMINATION_DATE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_ACCOUNT''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_CUSTOMER_ACCOUNT  L WHERE L.CUST_ACCOUNT_ID = x.CUST_ACCOUNT_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_customer_account
            SET
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                account_number = agis_lookup_xml_data_rec.account_number,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                account_name = agis_lookup_xml_data_rec.account_name,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                status = agis_lookup_xml_data_rec.status,
                account_termination_date = agis_lookup_xml_data_rec.account_termination_date
            WHERE
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_customer_account (
            cust_account_id,
            account_number,
            creation_date,
            account_name,
            last_update_date,
            attribute3,
            status,
            account_termination_date
        )
            ( SELECT
                x.cust_account_id,
                x.account_number,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.account_name,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                attribute3,
                status,
                to_char(to_date(substr(x.account_termination_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY')
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        cust_account_id NUMBER PATH './CUST_ACCOUNT_ID',
                        account_number VARCHAR2(240) PATH './ACCOUNT_NUMBER',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        account_name VARCHAR2(300) PATH './ACCOUNT_NAME',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        attribute3 VARCHAR2(150) PATH './ATTRIBUTE3',
                        status VARCHAR2(150) PATH './STATUS',
                        account_termination_date VARCHAR2(240) PATH './ACCOUNT_TERMINATION_DATE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_ACCOUNT'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_customer_account l
                    WHERE
                        l.cust_account_id = x.cust_account_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_customer_account_insert_update',
            p_tracker => 'agis_customer_account_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_customer_account_insert_update');
    END agis_customer_account_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_PARTY_SITES_INSERT_UPDATE
	*
	*  Description:  Syncs System Options BIP Report into XXAGIS_CUSTOMER_PARTY_SITES table
	*
	**************************************************************************/

    PROCEDURE agis_customer_party_sites_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            party_site_id     xxagis_customer_party_sites.party_site_id%TYPE,
            party_site_name   xxagis_customer_party_sites.party_site_name%TYPE,
            cust_account_id   xxagis_customer_party_sites.cust_account_id%TYPE,
            party_site_number xxagis_customer_party_sites.party_site_number%TYPE,
            creation_date     xxagis_customer_party_sites.creation_date%TYPE,
            last_update_date  xxagis_customer_party_sites.last_update_date%TYPE,
            status            xxagis_customer_party_sites.status%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_customer_party_sites_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_PARTY_SITES',
        'AGIS_CUSTOMER_PARTY_SITES');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PARTY_SITE_ID
				,x.PARTY_SITE_NAME
				,x.CUST_ACCOUNT_ID
				,x.PARTY_SITE_NUMBER
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,STATUS

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PARTY_SITE_ID NUMBER PATH ''./PARTY_SITE_ID''
										  ,PARTY_SITE_NAME VARCHAR2(240) PATH ''./PARTY_SITE_NAME''
										  ,CUST_ACCOUNT_ID VARCHAR2(240) PATH ''./CUST_ACCOUNT_ID''
										  ,PARTY_SITE_NUMBER VARCHAR2(300) PATH ''./PARTY_SITE_NUMBER''
										  ,CREATION_DATE VARCHAR2(300) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(300) PATH ''./LAST_UPDATE_DATE''
										  ,STATUS VARCHAR2(300) PATH ''./STATUS''
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_PARTY_SITES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_CUSTOMER_PARTY_SITES  L WHERE L.PARTY_SITE_ID = x.PARTY_SITE_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_customer_party_sites
            SET
                party_site_id = agis_lookup_xml_data_rec.party_site_id,
                party_site_name = agis_lookup_xml_data_rec.party_site_name,
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                party_site_number = agis_lookup_xml_data_rec.party_site_number,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                status = agis_lookup_xml_data_rec.status
            WHERE
                party_site_id = agis_lookup_xml_data_rec.party_site_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_customer_party_sites (
            party_site_id,
            party_site_name,
            cust_account_id,
            party_site_number,
            creation_date,
            last_update_date,
            status
        )
            ( SELECT
                x.party_site_id,
                x.party_site_name,
                x.cust_account_id,
                x.party_site_number,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                status
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        party_site_id NUMBER PATH './PARTY_SITE_ID',
                        party_site_name VARCHAR2(240) PATH './PARTY_SITE_NAME',
                        cust_account_id VARCHAR2(240) PATH './CUST_ACCOUNT_ID',
                        party_site_number VARCHAR2(300) PATH './PARTY_SITE_NUMBER',
                        creation_date VARCHAR2(300) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(300) PATH './LAST_UPDATE_DATE',
                        status VARCHAR2(300) PATH './STATUS'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_PARTY_SITES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_customer_party_sites l
                    WHERE
                        l.party_site_id = x.party_site_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_customer_party_sites_insert_update',
            p_tracker => 'agis_customer_party_sites_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_customer_party_sites_insert_update');
    END agis_customer_party_sites_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_ACCOUNT_SITES_INSERT_UPDATE
	*
	*  Description:  Syncs System Options BIP Report into XXAGIS_CUSTOMER_ACCOUNT_SITES_ALL table
	*
	**************************************************************************/

    PROCEDURE agis_customer_account_sites_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            party_site_id     xxagis_customer_account_sites_all.party_site_id%TYPE,
            cust_acct_site_id xxagis_customer_account_sites_all.cust_acct_site_id%TYPE,
            cust_account_id   xxagis_customer_account_sites_all.cust_account_id%TYPE,
            creation_date     xxagis_customer_account_sites_all.creation_date%TYPE,
            last_update_date  xxagis_customer_account_sites_all.last_update_date%TYPE,
            status            xxagis_customer_account_sites_all.status%TYPE,
            start_date        xxagis_customer_account_sites_all.start_date%TYPE,
            end_date          xxagis_customer_account_sites_all.end_date%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_customer_account_sites_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_ACCOUNT_SITES_ALL',
        'AGIS_CUSTOMER_ACCOUNT_SITES_ALL');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PARTY_SITE_ID
				,x.CUST_ACCT_SITE_ID
				,x.CUST_ACCOUNT_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,STATUS
				,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PARTY_SITE_ID NUMBER PATH ''./PARTY_SITE_ID''
										  ,CUST_ACCT_SITE_ID NUMBER PATH ''./CUST_ACCT_SITE_ID''
										  ,CUST_ACCOUNT_ID NUMBER PATH ''./CUST_ACCOUNT_ID''
										  ,CREATION_DATE VARCHAR2(300) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(300) PATH ''./LAST_UPDATE_DATE''
										  ,STATUS VARCHAR2(300) PATH ''./STATUS''
										  ,START_DATE VARCHAR2(300) PATH ''./START_DATE''
										 ,END_DATE VARCHAR2(300) PATH ''./END_DATE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_ACCOUNT_SITES_ALL''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_CUSTOMER_ACCOUNT_SITES_ALL  L WHERE L.CUST_ACCT_SITE_ID = x.CUST_ACCT_SITE_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_customer_account_sites_all
            SET
                party_site_id = agis_lookup_xml_data_rec.party_site_id,
                cust_acct_site_id = agis_lookup_xml_data_rec.cust_acct_site_id,
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                status = agis_lookup_xml_data_rec.status,
                start_date = agis_lookup_xml_data_rec.start_date,
                end_date = agis_lookup_xml_data_rec.end_date
            WHERE
                cust_acct_site_id = agis_lookup_xml_data_rec.cust_acct_site_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_customer_account_sites_all (
            party_site_id,
            cust_acct_site_id,
            cust_account_id,
            creation_date,
            last_update_date,
            status,
            start_date,
            end_date
        )
            ( SELECT
                x.party_site_id,
                x.cust_acct_site_id,
                x.cust_account_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                status,
                to_char(to_date(substr(x.start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY')
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        party_site_id NUMBER PATH './PARTY_SITE_ID',
                        cust_acct_site_id NUMBER PATH './CUST_ACCT_SITE_ID',
                        cust_account_id NUMBER PATH './CUST_ACCOUNT_ID',
                        creation_date VARCHAR2(300) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(300) PATH './LAST_UPDATE_DATE',
                        status VARCHAR2(300) PATH './STATUS',
                        start_date VARCHAR2(300) PATH './START_DATE',
                        end_date VARCHAR2(300) PATH './END_DATE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_customer_account_sites_all l
                    WHERE
                        l.cust_acct_site_id = x.cust_acct_site_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_customer_account_sites_insert_update',
            p_tracker => 'agis_customer_account_sites_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_customer_account_sites_insert_update');
    END agis_customer_account_sites_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_SITE_USE_INSERT_UPDATE
	*
	*  Description:  Syncs Customer Account site use BIP Report into XXAGIS_CUSTOMER_SITE_USE_ALL table
	*
	**************************************************************************/

    PROCEDURE agis_customer_site_use_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            primary_flag      xxagis_customer_site_use_all.primary_flag%TYPE,
            site_use_code     xxagis_customer_site_use_all.site_use_code%TYPE,
            site_use_id       xxagis_customer_site_use_all.site_use_id%TYPE,
            cust_acct_site_id xxagis_customer_site_use_all.cust_acct_site_id%TYPE,
            cust_account_id   xxagis_customer_site_use_all.cust_account_id%TYPE,
            creation_date     xxagis_customer_site_use_all.creation_date%TYPE,
            last_update_date  xxagis_customer_site_use_all.last_update_date%TYPE,
            status            xxagis_customer_site_use_all.status%TYPE,
            location          xxagis_customer_site_use_all.location%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_customer_account_sites_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_SITES_USE',
        'AGIS_CUSTOMER_SITES_USE');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PRIMARY_FLAG
				,SITE_USE_CODE
				,SITE_USE_ID
				,x.CUST_ACCT_SITE_ID
				,x.CUST_ACCOUNT_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,STATUS
				,LOCATION
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PRIMARY_FLAG VARCHAR2(150) PATH ''./PRIMARY_FLAG''
										  ,SITE_USE_CODE VARCHAR2(150) PATH ''./SITE_USE_CODE''
										  ,SITE_USE_ID NUMBER PATH ''./SITE_USE_ID''
										  ,CUST_ACCT_SITE_ID NUMBER PATH ''./CUST_ACCT_SITE_ID''
										  ,CUST_ACCOUNT_ID NUMBER PATH ''./CUST_ACCOUNT_ID''
										  ,CREATION_DATE VARCHAR2(300) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(300) PATH ''./LAST_UPDATE_DATE''
										  ,STATUS VARCHAR2(300) PATH ''./STATUS''
										   ,LOCATION VARCHAR2(300) PATH ''./LOCATION''
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_SITES_USE''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_CUSTOMER_SITE_USE_ALL  L WHERE L.SITE_USE_ID = x.SITE_USE_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_customer_site_use_all
            SET
                primary_flag = agis_lookup_xml_data_rec.primary_flag,
                site_use_code = agis_lookup_xml_data_rec.site_use_code,
                site_use_id = agis_lookup_xml_data_rec.site_use_id,
                cust_acct_site_id = agis_lookup_xml_data_rec.cust_acct_site_id,
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                status = agis_lookup_xml_data_rec.status,
                location = agis_lookup_xml_data_rec.location
            WHERE
                site_use_id = agis_lookup_xml_data_rec.site_use_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_customer_site_use_all (
            primary_flag,
            site_use_code,
            site_use_id,
            cust_acct_site_id,
            cust_account_id,
            creation_date,
            last_update_date,
            status,
            location
        )
            ( SELECT
                x.primary_flag,
                x.site_use_code,
                x.site_use_id,
                x.cust_acct_site_id,
                x.cust_account_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.status,
                x.location
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        primary_flag VARCHAR2(150) PATH './PRIMARY_FLAG',
                        site_use_code VARCHAR2(150) PATH './SITE_USE_CODE',
                        site_use_id NUMBER PATH './SITE_USE_ID',
                        cust_acct_site_id NUMBER PATH './CUST_ACCT_SITE_ID',
                        cust_account_id NUMBER PATH './CUST_ACCOUNT_ID',
                        creation_date VARCHAR2(300) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(300) PATH './LAST_UPDATE_DATE',
                        status VARCHAR2(300) PATH './STATUS',
                        location VARCHAR2(1000) PATH './LOCATION'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_SITES_USE'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_customer_site_use_all l
                    WHERE
                        l.site_use_id = x.site_use_id
                )
            );

	--CEN-8040 starts
	DELETE FROM XXAGIS_CUSTOMER_SITE_USE_ALL 
	WHERE ROWID IN 
		(SELECT ROWID 
			FROM
				(SELECT ROWID,
						SITE_USE_ID,
						ROW_NUMBER() OVER(PARTITION BY SITE_USE_ID ORDER BY LAST_UPDATE_DATE DESC) ROWN 
					FROM XXAGIS_CUSTOMER_SITE_USE_ALL
				)
			WHERE ROWN > 1
		) ;
	COMMIT ;
	--CEN-8040 ends

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_customer_site_use_insert_update',
            p_tracker => 'agis_customer_site_use_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_customer_site_use_insert_update');
    END agis_customer_site_use_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE_INSERT_UPDATE
	*
	*  Description:  Syncs Customer Account site use BIP Report into XXAGIS_CUSTOMER_ACCOUNT_SITE_PROFILE table
	*
	**************************************************************************/

    PROCEDURE agis_customer_account_site_profile_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            payment_terms           xxagis_customer_account_site_profile.payment_terms%TYPE,
            cust_account_profile_id xxagis_customer_account_site_profile.cust_account_profile_id%TYPE,
            cust_account_id         xxagis_customer_account_site_profile.cust_account_id%TYPE,
            creation_date           xxagis_customer_account_site_profile.creation_date%TYPE,
            last_update_date        xxagis_customer_account_site_profile.last_update_date%TYPE,
            status                  xxagis_customer_account_site_profile.status%TYPE,
            site_use_id             xxagis_customer_account_site_profile.site_use_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'agis_customer_account_sites_insert_update', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE',
        'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PAYMENT_TERMS
				,x.CUST_ACCOUNT_PROFILE_ID
				,x.CUST_ACCOUNT_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,STATUS
				,SITE_USE_ID
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PAYMENT_TERMS VARCHAR2(150) PATH ''./PAYMENT_TERMS''
										  ,CUST_ACCOUNT_PROFILE_ID NUMBER PATH ''./CUST_ACCOUNT_PROFILE_ID''
										  ,CUST_ACCOUNT_ID NUMBER PATH ''./CUST_ACCOUNT_ID''
										  ,CREATION_DATE VARCHAR2(300) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(300) PATH ''./LAST_UPDATE_DATE''
										  ,STATUS VARCHAR2(300) PATH ''./STATUS''
										  ,SITE_USE_ID NUMBER PATH ''./SITE_USE_ID''
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_CUSTOMER_ACCOUNT_SITE_PROFILE  L WHERE L.CUST_ACCOUNT_PROFILE_ID = x.CUST_ACCOUNT_PROFILE_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_customer_account_site_profile
            SET
                payment_terms = agis_lookup_xml_data_rec.payment_terms,
                cust_account_profile_id = agis_lookup_xml_data_rec.cust_account_profile_id,
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                status = agis_lookup_xml_data_rec.status,
                site_use_id = agis_lookup_xml_data_rec.site_use_id
            WHERE
                cust_account_profile_id = agis_lookup_xml_data_rec.cust_account_profile_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_customer_account_site_profile (
            payment_terms,
            cust_account_profile_id,
            cust_account_id,
            creation_date,
            last_update_date,
            status,
            site_use_id
        )
            ( SELECT
                x.payment_terms,
                x.cust_account_profile_id,
                x.cust_account_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                status,
                site_use_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        payment_terms VARCHAR2(150) PATH './PAYMENT_TERMS',
                        cust_account_profile_id NUMBER PATH './CUST_ACCOUNT_PROFILE_ID',
                        cust_account_id NUMBER PATH './CUST_ACCOUNT_ID',
                        creation_date VARCHAR2(300) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(300) PATH './LAST_UPDATE_DATE',
                        status VARCHAR2(300) PATH './STATUS',
                        site_use_id NUMBER PATH './SITE_USE_ID'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_customer_account_site_profile l
                    WHERE
                        l.cust_account_profile_id = x.cust_account_profile_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_customer_account_site_profile_insert_update',
            p_tracker => 'agis_customer_account_site_profile_insert_update', p_custom_err_info => 'EXCEPTION3 : agis_customer_account_site_profile_insert_update');
    END agis_customer_account_site_profile_insert_update;

    PROCEDURE agis_execute_bip_report_procs (
        p_user_name VARCHAR2
    ) AS
        return_status VARCHAR2(10);
    BEGIN
			   ------log----------
        writetolog('xxagis_utility_pkg', 'AGIS_EXECUTE_BIP_REPORT_PROCS', 'STATEMENT', 'Start Time: '
                                                                                       || sysdate
                                                                                       || ' User: '
                                                                                       || p_user_name, p_user_name);
			 ------------------------
        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_EXECUTE_BIP_REPORT_PROCS', p_tracker =>
        'BEGIN', p_custom_err_info => 'P_USER_NAME' || p_user_name);

        dbms_output.put_line('TRIGGER AGIS_VALUE_SET_VALUES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_VALUE_SET_VALUES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_LOOKUP_VALUES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_LOOKUP_VALUES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_GL_CALENDAR');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_GL_CALENDAR', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_GL_DATES');
        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_EXECUTE_BIP_REPORT_PROCS', p_tracker =>
        'TRIGGER AGIS_GL_DATES', p_custom_err_info => 'P_USER_NAME' || p_user_name);

        xxagis_utility_pkg.agis_call_bip_report('AGIS_GL_DATES', p_user_name);
        dbms_output.put_line('TRIGGER USER_ROLE_REPORT');
        xxagis_utility_pkg.agis_call_bip_report('USER_ROLE_REPORT', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_SYSTEM_OPTIONS');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_SYSTEM_OPTIONS', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_PERIOD_STATUSES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_PERIOD_STATUSES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_GL_PERIOD_STATUSES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_GL_PERIOD_STATUSES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_GL_PERIODS');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_GL_PERIODS', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_GL_LEDGER');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_GL_LEDGER', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_INTERCO_ORGANIZATIONS');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_INTERCO_ORGANIZATIONS', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_ACCOUNT');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_ACCOUNT', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_PARTY_SITES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_PARTY_SITES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_ACCOUNT_SITES_ALL');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_ACCOUNT_SITES_ALL', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_SITES_USE');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_SITES_USE', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_RELATED_PARTY_HIERACHY');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_RELATED_PARTY_HIERACHY', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_ERROR_MESSAGES_INSERT_UPDATE');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_ERROR_MESSAGES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_POZ_SUPPLIER_SITES');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_POZ_SUPPLIER_SITES', p_user_name);
        dbms_output.put_line('TRIGGER AGIS_CUSTOMER_SUPPLY_MAP');
        xxagis_utility_pkg.agis_call_bip_report('AGIS_CUSTOMER_SUPPLY_MAP', p_user_name);
			------log----------
        writetolog('xxagis_utility_pkg', 'AGIS_EXECUTE_BIP_REPORT_PROCS', 'STATEMENT', 'End Time: '
                                                                                       || sysdate
                                                                                       || ' User: '
                                                                                       || p_user_name, p_user_name);
			 ------------------------
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_EXECUTE_BIP_REPORT_PROCS', p_tracker =>
            'AGIS_EXECUTE_BIP_REPORT_PROCS', p_custom_err_info => 'EXCEPTION3 : AGIS_EXECUTE_BIP_REPORT_PROCS');
    END;

    FUNCTION get_agis_logs_zip (
        file_id_p NUMBER
    ) RETURN BLOB IS

        l_zip_file BLOB;

        CURSOR fileheader IS
        SELECT
            *
        FROM
            xxagis_file_header
        WHERE
            file_id = file_id_p;

    BEGIN
        FOR h IN fileheader LOOP
            IF ( h.agis_int_load_logs IS NOT NULL ) THEN
                apex_zip.add_file(p_zipped_blob => l_zip_file, p_file_name => 'AGIS INTERFACE.ZIP', p_content => h.agis_int_load_logs);
            END IF;

            IF ( h.agis_load_logs IS NOT NULL ) THEN
                apex_zip.add_file(p_zipped_blob => l_zip_file, p_file_name => 'AGIS BASE.ZIP', p_content => h.agis_load_logs);

            END IF;

            IF ( h.ar_int_load_logs IS NOT NULL ) THEN
                apex_zip.add_file(p_zipped_blob => l_zip_file, p_file_name => 'AR INTERFACE.ZIP', p_content => h.ar_int_load_logs);
            END IF;

            IF ( h.ar_load_logs IS NOT NULL ) THEN
                apex_zip.add_file(p_zipped_blob => l_zip_file, p_file_name => 'AR BASE.ZIP', p_content => h.ar_load_logs);
            END IF;

	/*CEN-8274_3_Start*/
			IF (h.error_message IS NOT NULL) THEN
			apex_zip.add_file(p_zipped_blob => l_zip_file, p_file_name => 'OIC ERROR LOG.TXT', p_content => utl_raw.cast_to_raw(h.error_message));
			END IF;
	/*CEN-8274_3_End*/

        END LOOP;

        apex_zip.finish(p_zipped_blob => l_zip_file);
        RETURN l_zip_file;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'GET_AGIS_LOGS_ZIP', p_tracker => 'GET_AGIS_LOGS_ZIP',
            p_custom_err_info => 'EXCEPTION3 : GET_AGIS_LOGS_ZIP');
    END;
	/***************************************************************************
	*
	*  PROCEDURE: AGIS_RELATED_PARTY_HIERACHY_INSERT_UPDATE
	*
	*  Description:  Syncs Related Party Hierachy BIP Report into XXAGIS_RELATED_PARTY_HIERARCHY table
	*
	**************************************************************************/

    PROCEDURE agis_related_party_hierarchy_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            parent              xxagis_related_party_hierarchy.parent%TYPE,
            child               xxagis_related_party_hierarchy.child%TYPE,
            tree_structure_code xxagis_related_party_hierarchy.tree_structure_code%TYPE,
            tree_code           xxagis_related_party_hierarchy.tree_code%TYPE,
            tree_node_id        xxagis_related_party_hierarchy.tree_node_id%TYPE,
            creation_date       xxagis_related_party_hierarchy.creation_date%TYPE,
            last_update_date    xxagis_related_party_hierarchy.last_update_date%TYPE,
            tree_version_id     xxagis_related_party_hierarchy.tree_version_id%TYPE,
            enterprise_id       xxagis_related_party_hierarchy.enterprise_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'XXAGIS_RELATED_PARTY_HIERARCHY', 'STATEMENT', 'Procedure running for report : AGIS_RELATED_PARTY_HIERACHY',
        'AGIS_RELATED_PARTY_HIERACHY');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.PARENT
				,CHILD
				,TREE_STRUCTURE_CODE
				,x.TREE_CODE
				,x.TREE_NODE_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TREE_VERSION_ID
				,ENTERPRISE_ID

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  PARENT VARCHAR2(100) PATH ''./PARENT''
										  ,CHILD VARCHAR2(100) PATH ''./CHILD''
										  ,TREE_STRUCTURE_CODE VARCHAR2(100) PATH ''./TREE_STRUCTURE_CODE''
										  ,TREE_CODE VARCHAR2(100) PATH ''./TREE_CODE''
										  ,TREE_NODE_ID VARCHAR2(100) PATH ''./TREE_NODE_ID''
										  ,CREATION_DATE VARCHAR2(100) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(100) PATH ''./LAST_UPDATE_DATE''
										  ,TREE_VERSION_ID VARCHAR2(100) PATH ''./TREE_VERSION_ID''
										  ,ENTERPRISE_ID VARCHAR2(100) PATH ''./ENTERPRISE_ID''
										  ) x
				WHERE t.template_name LIKE ''AGIS_RELATED_PARTY_HIERACHY''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_RELATED_PARTY_HIERARCHY  L WHERE L.TREE_STRUCTURE_CODE = x.TREE_STRUCTURE_CODE
																			AND L.TREE_CODE = x.TREE_CODE
																			AND L.TREE_VERSION_ID = x.TREE_VERSION_ID '
																			--3-30676503231 changes start
                                                                            --AND L.TREE_NODE_ID = x.TREE_NODE_ID                           
                                     || 'AND L.PARENT = X.PARENT
                                                                            AND L.CHILD = X.CHILD '
                                                                            --3-30676503231 changes end
                                     || 'AND L.ENTERPRISE_ID = x.ENTERPRISE_ID)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_related_party_hierarchy
            SET
                parent = agis_lookup_xml_data_rec.parent,
                child = agis_lookup_xml_data_rec.child,
                tree_structure_code = agis_lookup_xml_data_rec.tree_structure_code,
                tree_code = agis_lookup_xml_data_rec.tree_code,
                tree_node_id = agis_lookup_xml_data_rec.tree_node_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                tree_version_id = agis_lookup_xml_data_rec.tree_version_id,
                enterprise_id = agis_lookup_xml_data_rec.enterprise_id
            WHERE
                    tree_structure_code = agis_lookup_xml_data_rec.tree_structure_code
                AND tree_code = agis_lookup_xml_data_rec.tree_code
                AND tree_version_id = agis_lookup_xml_data_rec.tree_version_id
                    --3-30676503231 changes start
--					AND TREE_NODE_ID = agis_lookup_xml_data_rec.TREE_NODE_ID                                
                AND parent = agis_lookup_xml_data_rec.parent
                AND child = agis_lookup_xml_data_rec.child
                    --3-30676503231 changes end
                AND enterprise_id = agis_lookup_xml_data_rec.enterprise_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_related_party_hierarchy (
            parent,
            child,
            tree_structure_code,
            tree_code,
            tree_node_id,
            creation_date,
            last_update_date,
            tree_version_id,
            enterprise_id
        )
            ( SELECT
                x.parent,
                x.child,
                x.tree_structure_code,
                x.tree_code,
                x.tree_node_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                tree_version_id,
                enterprise_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        parent VARCHAR2(100) PATH './PARENT',
                        child VARCHAR2(100) PATH './CHILD',
                        tree_structure_code VARCHAR2(100) PATH './TREE_STRUCTURE_CODE',
                        tree_code VARCHAR2(100) PATH './TREE_CODE',
                        tree_node_id VARCHAR2(100) PATH './TREE_NODE_ID',
                        creation_date VARCHAR2(100) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(100) PATH './LAST_UPDATE_DATE',
                        tree_version_id VARCHAR2(100) PATH './TREE_VERSION_ID',
                        enterprise_id VARCHAR2(100) PATH './ENTERPRISE_ID'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_RELATED_PARTY_HIERACHY'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_related_party_hierarchy l
                    WHERE
                            l.tree_structure_code = x.tree_structure_code
                        AND l.tree_code = x.tree_code
                        AND l.tree_version_id = x.tree_version_id
                --3-30676503231 changes start
--				AND L.TREE_NODE_ID = x.TREE_NODE_ID                           
                        AND l.parent = x.parent
                        AND l.child = x.child
                --3-30676503231 changes end
                        AND l.enterprise_id = x.enterprise_id
                )
            );

            --CEN-2985 | SR 3-32323763401 starts
			DELETE 
			FROM xxagis_related_party_hierarchy
			WHERE
				ROWID IN (SELECT
						ROWID
					FROM
						(SELECT
								ROWID, child,  ROW_NUMBER() 
								OVER(PARTITION BY child ORDER BY last_update_date DESC) rown
							FROM
								xxagis_related_party_hierarchy)
					WHERE
						rown > 1);
            commit;   	
           --CEN-2985 | SR 3-32323763401 ends

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_RELATED_PARTY_HIERARCHY_INSERT_UPDATE',
            p_tracker => 'AGIS_RELATED_PARTY_HIERARCHY_INSERT_UPDATE', p_custom_err_info => 'EXCEPTION3 : AGIS_RELATED_PARTY_HIERARCHY_INSERT_UPDATE');
    END agis_related_party_hierarchy_insert_update;

	/***************************************************************************
	*
	*  PROCEDURE: AGIS_CUSTOMER_SUPPLY_MAP_INSERT_UPDATE
	*
	*  Description:  Syncs AGIS - Interco Customer Supplier Map BIP Report into XXAGIS_FUN_IC_CUST_SUPP_MAP table
	*
	**************************************************************************/

    PROCEDURE agis_customer_supply_map_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            cust_supp_map_id      xxagis_fun_ic_cust_supp_map.cust_supp_map_id%TYPE,
            legal_entity_id       xxagis_fun_ic_cust_supp_map.legal_entity_id%TYPE,
            creation_date         xxagis_fun_ic_cust_supp_map.creation_date%TYPE,
            created_by            xxagis_fun_ic_cust_supp_map.created_by%TYPE,
            last_update_date      xxagis_fun_ic_cust_supp_map.last_update_date%TYPE,
            last_updated_by       xxagis_fun_ic_cust_supp_map.last_updated_by%TYPE,
            last_update_login     xxagis_fun_ic_cust_supp_map.last_update_login%TYPE,
            cust_account_id       xxagis_fun_ic_cust_supp_map.cust_account_id%TYPE,
            vendor_id             xxagis_fun_ic_cust_supp_map.vendor_id%TYPE,
            attribute_category    xxagis_fun_ic_cust_supp_map.attribute_category%TYPE,
            attribute6            xxagis_fun_ic_cust_supp_map.attribute6%TYPE,
            attribute7            xxagis_fun_ic_cust_supp_map.attribute7%TYPE,
            attribute8            xxagis_fun_ic_cust_supp_map.attribute8%TYPE,
            attribute9            xxagis_fun_ic_cust_supp_map.attribute9%TYPE,
            attribute10           xxagis_fun_ic_cust_supp_map.attribute10%TYPE,
            attribute11           xxagis_fun_ic_cust_supp_map.attribute11%TYPE,
            attribute12           xxagis_fun_ic_cust_supp_map.attribute12%TYPE,
            attribute13           xxagis_fun_ic_cust_supp_map.attribute13%TYPE,
            attribute14           xxagis_fun_ic_cust_supp_map.attribute14%TYPE,
            attribute1            xxagis_fun_ic_cust_supp_map.attribute1%TYPE,
            attribute2            xxagis_fun_ic_cust_supp_map.attribute2%TYPE,
            attribute3            xxagis_fun_ic_cust_supp_map.attribute3%TYPE,
            attribute4            xxagis_fun_ic_cust_supp_map.attribute4%TYPE,
            attribute5            xxagis_fun_ic_cust_supp_map.attribute5%TYPE,
            attribute15           xxagis_fun_ic_cust_supp_map.attribute15%TYPE,
            attribute16           xxagis_fun_ic_cust_supp_map.attribute16%TYPE,
            attribute17           xxagis_fun_ic_cust_supp_map.attribute17%TYPE,
            attribute18           xxagis_fun_ic_cust_supp_map.attribute18%TYPE,
            attribute19           xxagis_fun_ic_cust_supp_map.attribute19%TYPE,
            attribute20           xxagis_fun_ic_cust_supp_map.attribute20%TYPE,
            object_version_number xxagis_fun_ic_cust_supp_map.object_version_number%TYPE,
            interco_org_id        xxagis_fun_ic_cust_supp_map.interco_org_id%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'AGIS_CUSTOMER_SUPPLY_MAP_INSERT_UPDATE', 'STATEMENT', 'Procedure running for report : AGIS_CUSTOMER_SUPPLY_MAP',
        'AGIS_CUSTOMER_SUPPLY_MAP');

	----Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.CUST_SUPP_MAP_ID 
				,x.LEGAL_ENTITY_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,x.CUST_ACCOUNT_ID 
				,x.VENDOR_ID 
				,ATTRIBUTE_CATEGORY
				,ATTRIBUTE6 
				,ATTRIBUTE7
				,ATTRIBUTE8
				,x.ATTRIBUTE9
				,x.ATTRIBUTE10
				,x.ATTRIBUTE11
				,x.ATTRIBUTE12
				,ATTRIBUTE13                        
				,ATTRIBUTE14              
				,ATTRIBUTE1                           
				,ATTRIBUTE2                           
				,ATTRIBUTE3                           
				,ATTRIBUTE4                           
				,ATTRIBUTE5                           
				,ATTRIBUTE15                              
				,ATTRIBUTE16           
				,ATTRIBUTE17        
				,ATTRIBUTE18                            
				,ATTRIBUTE19                
				,ATTRIBUTE20 
				,OBJECT_VERSION_NUMBER
				,INTERCO_ORG_ID

				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  CUST_SUPP_MAP_ID  NUMBER PATH ''./CUST_SUPP_MAP_ID ''
										  ,LEGAL_ENTITY_ID NUMBER PATH ''./LEGAL_ENTITY_ID''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,CUST_ACCOUNT_ID  NUMBER PATH ''./CUST_ACCOUNT_ID ''
										  ,VENDOR_ID  NUMBER PATH ''./VENDOR_ID ''
										  ,ATTRIBUTE_CATEGORY VARCHAR2(240) PATH ''./ATTRIBUTE_CATEGORY''
										  ,ATTRIBUTE6  VARCHAR2(240) PATH ''./ATTRIBUTE6 ''
										  ,ATTRIBUTE7 VARCHAR2(240) PATH ''./ATTRIBUTE7''
										  ,ATTRIBUTE8 VARCHAR2(240) PATH ''./ATTRIBUTE8''
										  ,ATTRIBUTE9 VARCHAR2(240) PATH ''./ATTRIBUTE9''
										  ,ATTRIBUTE10 VARCHAR2(240) PATH ''./ATTRIBUTE10''
										  ,ATTRIBUTE11 VARCHAR2(240) PATH ''./ATTRIBUTE11''
										  ,ATTRIBUTE12 VARCHAR2(240) PATH ''./ATTRIBUTE12''
										  ,ATTRIBUTE13 VARCHAR2(240) PATH ''./ATTRIBUTE13''                        
										  ,ATTRIBUTE14 VARCHAR2(240) PATH ''./ATTRIBUTE14''              
										  ,ATTRIBUTE1 VARCHAR2(240) PATH ''./ATTRIBUTE1''                           
										  ,ATTRIBUTE2 VARCHAR2(240) PATH ''./ATTRIBUTE2''                           
										  ,ATTRIBUTE3 VARCHAR2(240) PATH ''./ATTRIBUTE3''                           
										  ,ATTRIBUTE4 VARCHAR2(240) PATH ''./ATTRIBUTE4''                           
										  ,ATTRIBUTE5 VARCHAR2(240) PATH ''./ATTRIBUTE5''                           
										  ,ATTRIBUTE15 VARCHAR2(240) PATH ''./ATTRIBUTE15''                              
										  ,ATTRIBUTE16 VARCHAR2(240) PATH ''./ATTRIBUTE16''           
										  ,ATTRIBUTE17 VARCHAR2(240) PATH ''./ATTRIBUTE17''        
										  ,ATTRIBUTE18 VARCHAR2(240) PATH ''./ATTRIBUTE18''                            
										  ,ATTRIBUTE19 VARCHAR2(240) PATH ''./ATTRIBUTE19''                
										  ,ATTRIBUTE20 VARCHAR2(240) PATH ''./ATTRIBUTE20''  
										  ,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER'' 
										  ,INTERCO_ORG_ID NUMBER PATH ''./INTERCO_ORG_ID'' 
										  ) x
				WHERE t.template_name LIKE ''AGIS_CUSTOMER_SUPPLY_MAP''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_FUN_IC_CUST_SUPP_MAP  L WHERE L.CUST_SUPP_MAP_ID  = x.CUST_SUPP_MAP_ID )' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_fun_ic_cust_supp_map
            SET
                cust_supp_map_id = agis_lookup_xml_data_rec.cust_supp_map_id,
                legal_entity_id = agis_lookup_xml_data_rec.legal_entity_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                cust_account_id = agis_lookup_xml_data_rec.cust_account_id,
                vendor_id = agis_lookup_xml_data_rec.vendor_id,
                attribute_category = agis_lookup_xml_data_rec.attribute_category,
                attribute6 = agis_lookup_xml_data_rec.attribute6,
                attribute7 = agis_lookup_xml_data_rec.attribute7,
                attribute8 = agis_lookup_xml_data_rec.attribute8,
                attribute9 = agis_lookup_xml_data_rec.attribute9,
                attribute10 = agis_lookup_xml_data_rec.attribute10,
                attribute11 = agis_lookup_xml_data_rec.attribute11,
                attribute12 = agis_lookup_xml_data_rec.attribute12,
                attribute13 = agis_lookup_xml_data_rec.attribute13,
                attribute14 = agis_lookup_xml_data_rec.attribute14,
                attribute1 = agis_lookup_xml_data_rec.attribute1,
                attribute2 = agis_lookup_xml_data_rec.attribute2,
                attribute3 = agis_lookup_xml_data_rec.attribute3,
                attribute4 = agis_lookup_xml_data_rec.attribute4,
                attribute5 = agis_lookup_xml_data_rec.attribute5,
                attribute15 = agis_lookup_xml_data_rec.attribute15,
                attribute16 = agis_lookup_xml_data_rec.attribute16,
                attribute17 = agis_lookup_xml_data_rec.attribute17,
                attribute18 = agis_lookup_xml_data_rec.attribute18,
                attribute19 = agis_lookup_xml_data_rec.attribute19,
                attribute20 = agis_lookup_xml_data_rec.attribute20,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                interco_org_id = agis_lookup_xml_data_rec.interco_org_id
            WHERE      --define the primary keys
                cust_supp_map_id = agis_lookup_xml_data_rec.cust_supp_map_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_fun_ic_cust_supp_map (
            cust_supp_map_id,
            legal_entity_id,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            cust_account_id,
            vendor_id,
            attribute_category,
            attribute6,
            attribute7,
            attribute8,
            attribute9,
            attribute10,
            attribute11,
            attribute12,
            attribute13,
            attribute14,
            attribute1,
            attribute2,
            attribute3,
            attribute4,
            attribute5,
            attribute15,
            attribute16,
            attribute17,
            attribute18,
            attribute19,
            attribute20,
            object_version_number,
            interco_org_id
        )
            ( SELECT
                x.cust_supp_map_id,
                x.legal_entity_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                x.cust_account_id,
                x.vendor_id,
                x.attribute_category,
                x.attribute6,
                x.attribute7,
                x.attribute8,
                x.attribute9,
                x.attribute10,
                x.attribute11,
                x.attribute12,
                x.attribute13,
                x.attribute14,
                x.attribute1,
                x.attribute2,
                x.attribute3,
                x.attribute4,
                x.attribute5,
                x.attribute15,
                x.attribute16,
                x.attribute17,
                x.attribute18,
                x.attribute19,
                x.attribute20,
                x.object_version_number,
                x.interco_org_id
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        cust_supp_map_id NUMBER PATH './CUST_SUPP_MAP_ID ',
                        legal_entity_id NUMBER PATH './LEGAL_ENTITY_ID',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        cust_account_id NUMBER PATH './CUST_ACCOUNT_ID ',
                        vendor_id NUMBER PATH './VENDOR_ID ',
                        attribute_category VARCHAR2(240) PATH './ATTRIBUTE_CATEGORY',
                        attribute6 VARCHAR2(240) PATH './ATTRIBUTE6 ',
                        attribute7 VARCHAR2(240) PATH './ATTRIBUTE7',
                        attribute8 VARCHAR2(240) PATH './ATTRIBUTE8',
                        attribute9 VARCHAR2(240) PATH './ATTRIBUTE9',
                        attribute10 VARCHAR2(240) PATH './ATTRIBUTE10',
                        attribute11 VARCHAR2(240) PATH './ATTRIBUTE11',
                        attribute12 VARCHAR2(240) PATH './ATTRIBUTE12',
                        attribute13 VARCHAR2(240) PATH './ATTRIBUTE13',
                        attribute14 VARCHAR2(240) PATH './ATTRIBUTE14',
                        attribute1 VARCHAR2(240) PATH './ATTRIBUTE1',
                        attribute2 VARCHAR2(240) PATH './ATTRIBUTE2',
                        attribute3 VARCHAR2(240) PATH './ATTRIBUTE3',
                        attribute4 VARCHAR2(240) PATH './ATTRIBUTE4',
                        attribute5 VARCHAR2(240) PATH './ATTRIBUTE5',
                        attribute15 VARCHAR2(240) PATH './ATTRIBUTE15',
                        attribute16 VARCHAR2(240) PATH './ATTRIBUTE16',
                        attribute17 VARCHAR2(240) PATH './ATTRIBUTE17',
                        attribute18 VARCHAR2(240) PATH './ATTRIBUTE18',
                        attribute19 VARCHAR2(240) PATH './ATTRIBUTE19',
                        attribute20 VARCHAR2(240) PATH './ATTRIBUTE20',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        interco_org_id NUMBER PATH './INTERCO_ORG_ID'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_CUSTOMER_SUPPLY_MAP'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_fun_ic_cust_supp_map l
                    WHERE
                        l.cust_supp_map_id = x.cust_supp_map_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_CUSTOMER_SUPPLY_MAP_INSERT_UPDATE',
            p_tracker => 'AGIS_CUSTOMER_SUPPLY_MAP_INSERT_UPDATE', p_custom_err_info => 'EXCEPTION3 : AGIS_CUSTOMER_SUPPLY_MAP_INSERT_UPDATE');
    END agis_customer_supply_map_insert_update;

	 /***************************************************************************
	*
	*  PROCEDURE: AGIS_POZ_SUPPLIER_SITES_INSERT_UPDATE
	*
	*  Description:  Syncs AGIS - POZ Supplier Sites BIP Report into XXAGIS_POZ_SUPPLIER_SITES_V table
	*
	**************************************************************************/

    PROCEDURE agis_poz_supplier_sites_insert_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_lookup_xml_data IS RECORD (
            vendor_site_spk_id             xxagis_poz_supplier_sites_v.vendor_site_spk_id%TYPE,
            vendor_site_id                 xxagis_poz_supplier_sites_v.vendor_site_id%TYPE,
            creation_date                  xxagis_poz_supplier_sites_v.creation_date%TYPE,
            created_by                     xxagis_poz_supplier_sites_v.created_by%TYPE,
            last_update_date               xxagis_poz_supplier_sites_v.last_update_date%TYPE,
            last_updated_by                xxagis_poz_supplier_sites_v.last_updated_by%TYPE,
            last_update_login              xxagis_poz_supplier_sites_v.last_update_login%TYPE,
            effective_end_date             xxagis_poz_supplier_sites_v.effective_end_date%TYPE,
            vendor_id                      xxagis_poz_supplier_sites_v.vendor_id%TYPE,
            object_version_number          xxagis_poz_supplier_sites_v.object_version_number%TYPE,
            inactive_date                  xxagis_poz_supplier_sites_v.inactive_date%TYPE,
            prc_bu_id                      xxagis_poz_supplier_sites_v.prc_bu_id%TYPE,
            location_id                    xxagis_poz_supplier_sites_v.location_id%TYPE,
            party_site_id                  xxagis_poz_supplier_sites_v.party_site_id%TYPE,
            vendor_site_code               xxagis_poz_supplier_sites_v.vendor_site_code%TYPE,
            purchasing_site_flag           xxagis_poz_supplier_sites_v.purchasing_site_flag%TYPE,
            rfq_only_site_flag             xxagis_poz_supplier_sites_v.rfq_only_site_flag%TYPE,
            pay_site_flag                  xxagis_poz_supplier_sites_v.pay_site_flag%TYPE,
            tp_header_id                   xxagis_poz_supplier_sites_v.tp_header_id%TYPE,
            tolerance_id                   xxagis_poz_supplier_sites_v.tolerance_id%TYPE,
            terms_id                       xxagis_poz_supplier_sites_v.terms_id%TYPE,
            exclude_freight_from_discount  xxagis_poz_supplier_sites_v.exclude_freight_from_discount%TYPE,
            bank_charge_bearer             xxagis_poz_supplier_sites_v.bank_charge_bearer%TYPE,
            pay_on_code                    xxagis_poz_supplier_sites_v.pay_on_code%TYPE,
            services_tolerance_id          xxagis_poz_supplier_sites_v.services_tolerance_id%TYPE,
            match_option                   xxagis_poz_supplier_sites_v.match_option%TYPE,
            country_of_origin_code         xxagis_poz_supplier_sites_v.country_of_origin_code%TYPE,
            create_debit_memo_flag         xxagis_poz_supplier_sites_v.create_debit_memo_flag%TYPE,
            supplier_notif_method          xxagis_poz_supplier_sites_v.supplier_notif_method%TYPE,
            email_address                  xxagis_poz_supplier_sites_v.email_address%TYPE,
            effective_start_date           xxagis_poz_supplier_sites_v.effective_start_date%TYPE,
            effective_sequence             xxagis_poz_supplier_sites_v.effective_sequence%TYPE,
            default_pay_site_id            xxagis_poz_supplier_sites_v.default_pay_site_id%TYPE,
            pay_on_receipt_summary_code    xxagis_poz_supplier_sites_v.pay_on_receipt_summary_code%TYPE,
            ece_tp_location_code           xxagis_poz_supplier_sites_v.ece_tp_location_code%TYPE,
            pcard_site_flag                xxagis_poz_supplier_sites_v.pcard_site_flag%TYPE,
            primary_pay_site_flag          xxagis_poz_supplier_sites_v.primary_pay_site_flag%TYPE,
            shipping_control               xxagis_poz_supplier_sites_v.shipping_control%TYPE,
            selling_company_identifier     xxagis_poz_supplier_sites_v.selling_company_identifier%TYPE,
            gapless_inv_num_flag           xxagis_poz_supplier_sites_v.gapless_inv_num_flag%TYPE,
            retainage_rate                 xxagis_poz_supplier_sites_v.retainage_rate%TYPE,
            auto_calculate_interest_flag   xxagis_poz_supplier_sites_v.auto_calculate_interest_flag%TYPE,
            hold_by                        xxagis_poz_supplier_sites_v.hold_by%TYPE,
            hold_date                      xxagis_poz_supplier_sites_v.hold_date%TYPE,
            hold_flag                      xxagis_poz_supplier_sites_v.hold_flag%TYPE,
            purchasing_hold_reason         xxagis_poz_supplier_sites_v.purchasing_hold_reason%TYPE,
            vendor_site_code_alt           xxagis_poz_supplier_sites_v.vendor_site_code_alt%TYPE,
            attention_ar_flag              xxagis_poz_supplier_sites_v.attention_ar_flag%TYPE,
            area_code                      xxagis_poz_supplier_sites_v.area_code%TYPE,
            phone                          xxagis_poz_supplier_sites_v.phone%TYPE,
            customer_num                   xxagis_poz_supplier_sites_v.customer_num%TYPE,
            ship_via_lookup_code           xxagis_poz_supplier_sites_v.ship_via_lookup_code%TYPE,
            freight_terms_lookup_code      xxagis_poz_supplier_sites_v.freight_terms_lookup_code%TYPE,
            fob_lookup_code                xxagis_poz_supplier_sites_v.fob_lookup_code%TYPE,
            fax                            xxagis_poz_supplier_sites_v.fax%TYPE,
            fax_area_code                  xxagis_poz_supplier_sites_v.fax_area_code%TYPE,
            telex                          xxagis_poz_supplier_sites_v.telex%TYPE,
            terms_date_basis               xxagis_poz_supplier_sites_v.terms_date_basis%TYPE,
            pay_group_lookup_code          xxagis_poz_supplier_sites_v.pay_group_lookup_code%TYPE,
            payment_priority               xxagis_poz_supplier_sites_v.payment_priority%TYPE,
            invoice_amount_limit           xxagis_poz_supplier_sites_v.invoice_amount_limit%TYPE,
            pay_date_basis_lookup_code     xxagis_poz_supplier_sites_v.pay_date_basis_lookup_code%TYPE,
            always_take_disc_flag          xxagis_poz_supplier_sites_v.always_take_disc_flag%TYPE,
            invoice_currency_code          xxagis_poz_supplier_sites_v.invoice_currency_code%TYPE,
            payment_currency_code          xxagis_poz_supplier_sites_v.payment_currency_code%TYPE,
            hold_all_payments_flag         xxagis_poz_supplier_sites_v.hold_all_payments_flag%TYPE,
            hold_future_payments_flag      xxagis_poz_supplier_sites_v.hold_future_payments_flag%TYPE,
            hold_reason                    xxagis_poz_supplier_sites_v.hold_reason%TYPE,
            hold_unmatched_invoices_flag   xxagis_poz_supplier_sites_v.hold_unmatched_invoices_flag%TYPE,
            payment_hold_date              xxagis_poz_supplier_sites_v.payment_hold_date%TYPE,
            tax_reporting_site_flag        xxagis_poz_supplier_sites_v.tax_reporting_site_flag%TYPE,
            request_id                     xxagis_poz_supplier_sites_v.request_id%TYPE,
            program_application_id         xxagis_poz_supplier_sites_v.program_application_id%TYPE,
            program_id                     xxagis_poz_supplier_sites_v.program_id%TYPE,
            program_update_date            xxagis_poz_supplier_sites_v.program_update_date%TYPE,
            global_attribute_category      xxagis_poz_supplier_sites_v.global_attribute_category%TYPE,
            carrier_id                     xxagis_poz_supplier_sites_v.carrier_id%TYPE,
            allow_substitute_receipts_flag xxagis_poz_supplier_sites_v.allow_substitute_receipts_flag%TYPE,
            allow_unordered_receipts_flag  xxagis_poz_supplier_sites_v.allow_unordered_receipts_flag%TYPE,
            enforce_ship_to_location_code  xxagis_poz_supplier_sites_v.enforce_ship_to_location_code%TYPE,
            qty_rcv_exception_code         xxagis_poz_supplier_sites_v.qty_rcv_exception_code%TYPE,
            receipt_days_exception_code    xxagis_poz_supplier_sites_v.receipt_days_exception_code%TYPE,
            inspection_required_flag       xxagis_poz_supplier_sites_v.inspection_required_flag%TYPE,
            receipt_required_flag          xxagis_poz_supplier_sites_v.receipt_required_flag%TYPE,
            qty_rcv_tolerance              xxagis_poz_supplier_sites_v.qty_rcv_tolerance%TYPE,
            days_early_receipt_allowed     xxagis_poz_supplier_sites_v.days_early_receipt_allowed%TYPE,
            days_late_receipt_allowed      xxagis_poz_supplier_sites_v.days_late_receipt_allowed%TYPE,
            receiving_routing_id           xxagis_poz_supplier_sites_v.receiving_routing_id%TYPE,
            shipping_network_location      xxagis_poz_supplier_sites_v.shipping_network_location%TYPE,
            fax_country_code               xxagis_poz_supplier_sites_v.fax_country_code%TYPE,
            tax_country_code               xxagis_poz_supplier_sites_v.tax_country_code%TYPE,
            aging_period_days              xxagis_poz_supplier_sites_v.aging_period_days%TYPE,
            aging_onset_point              xxagis_poz_supplier_sites_v.aging_onset_point%TYPE,
            consumption_advice_frequency   xxagis_poz_supplier_sites_v.consumption_advice_frequency%TYPE,
            consumption_advice_summary     xxagis_poz_supplier_sites_v.consumption_advice_summary%TYPE,
            pay_on_use_flag                xxagis_poz_supplier_sites_v.pay_on_use_flag%TYPE,
            mode_of_transport              xxagis_poz_supplier_sites_v.mode_of_transport%TYPE,
            service_level                  xxagis_poz_supplier_sites_v.service_level%TYPE,
            duns_number                    xxagis_poz_supplier_sites_v.duns_number%TYPE,
            party_site_name                xxagis_poz_supplier_sites_v.party_site_name%TYPE,
            party_status                   xxagis_poz_supplier_sites_v.party_status%TYPE,
            party_site_status              xxagis_poz_supplier_sites_v.party_site_status%TYPE,
            start_date_active              xxagis_poz_supplier_sites_v.start_date_active%TYPE,
            end_date_active                xxagis_poz_supplier_sites_v.end_date_active%TYPE
        );
        agis_lookup_xml_data_rec agis_lookup_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        writetolog('xxagis_utility_pkg', 'AGIS_POZ_SUPPLIER_SITES_INSERT_UPDATE', 'STATEMENT', 'Procedure running for report : AGIS_POZ_SUPPLIER_SITES',
        'AGIS_POZ_SUPPLIER_SITES');

	----Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 x.VENDOR_SITE_SPK_ID 
				,x.VENDOR_SITE_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.CREATED_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.LAST_UPDATED_BY
				,x.LAST_UPDATE_LOGIN
				,TO_CHAR(TO_DATE(SUBSTR(x.EFFECTIVE_END_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,x.VENDOR_ID 
				,OBJECT_VERSION_NUMBER
				,TO_CHAR(TO_DATE(SUBSTR(x.INACTIVE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,PRC_BU_ID
				,LOCATION_ID
				,x.PARTY_SITE_ID
				,x.VENDOR_SITE_CODE
				,x.PURCHASING_SITE_FLAG
				,x.RFQ_ONLY_SITE_FLAG
				,PAY_SITE_FLAG                        
				,TP_HEADER_ID              
				,TOLERANCE_ID                           
				,TERMS_ID                           
				,EXCLUDE_FREIGHT_FROM_DISCOUNT                           
				,BANK_CHARGE_BEARER                           
				,PAY_ON_CODE                           
				,SERVICES_TOLERANCE_ID                              
				,MATCH_OPTION           
				,COUNTRY_OF_ORIGIN_CODE        
				,CREATE_DEBIT_MEMO_FLAG                            
				,SUPPLIER_NOTIF_METHOD   
				,EMAIL_ADDRESS			
				,TO_CHAR(TO_DATE(SUBSTR(x.EFFECTIVE_START_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,EFFECTIVE_SEQUENCE
				,DEFAULT_PAY_SITE_ID
				,PAY_ON_RECEIPT_SUMMARY_CODE
				,ECE_TP_LOCATION_CODE
				,PCARD_SITE_FLAG
				,PRIMARY_PAY_SITE_FLAG
				,SHIPPING_CONTROL
				,SELLING_COMPANY_IDENTIFIER
				,GAPLESS_INV_NUM_FLAG
				,RETAINAGE_RATE
				,AUTO_CALCULATE_INTEREST_FLAG
				,HOLD_BY
				,TO_CHAR(TO_DATE(SUBSTR(x.HOLD_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,HOLD_FLAG
				,PURCHASING_HOLD_REASON
				,VENDOR_SITE_CODE_ALT
				,ATTENTION_AR_FLAG
				,AREA_CODE
				,PHONE
				,CUSTOMER_NUM
				,SHIP_VIA_LOOKUP_CODE
				,FREIGHT_TERMS_LOOKUP_CODE
				,FOB_LOOKUP_CODE
				,FAX
				,FAX_AREA_CODE
				,TELEX
				,TERMS_DATE_BASIS
				,PAY_GROUP_LOOKUP_CODE
				,PAYMENT_PRIORITY
				,INVOICE_AMOUNT_LIMIT
				,PAY_DATE_BASIS_LOOKUP_CODE
				,ALWAYS_TAKE_DISC_FLAG
				,INVOICE_CURRENCY_CODE
				,PAYMENT_CURRENCY_CODE
				,HOLD_ALL_PAYMENTS_FLAG
				,HOLD_FUTURE_PAYMENTS_FLAG
				,HOLD_REASON
				,HOLD_UNMATCHED_INVOICES_FLAG
				,TO_CHAR(TO_DATE(SUBSTR(x.PAYMENT_HOLD_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TAX_REPORTING_SITE_FLAG
				,REQUEST_ID
				,PROGRAM_APPLICATION_ID
				,PROGRAM_ID
				,TO_CHAR(TO_DATE(SUBSTR(x.PROGRAM_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,GLOBAL_ATTRIBUTE_CATEGORY
				,CARRIER_ID
				,ALLOW_SUBSTITUTE_RECEIPTS_FLAG
				,ALLOW_UNORDERED_RECEIPTS_FLAG
				,ENFORCE_SHIP_TO_LOCATION_CODE
				,QTY_RCV_EXCEPTION_CODE
				,RECEIPT_DAYS_EXCEPTION_CODE
				,INSPECTION_REQUIRED_FLAG
				,RECEIPT_REQUIRED_FLAG
				,QTY_RCV_TOLERANCE
				,DAYS_EARLY_RECEIPT_ALLOWED
				,DAYS_LATE_RECEIPT_ALLOWED
				,RECEIVING_ROUTING_ID
				,SHIPPING_NETWORK_LOCATION
				,FAX_COUNTRY_CODE
				,TAX_COUNTRY_CODE
				,TO_CHAR(TO_DATE(SUBSTR(x.AGING_PERIOD_DAYS, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,AGING_ONSET_POINT
				,CONSUMPTION_ADVICE_FREQUENCY
				,CONSUMPTION_ADVICE_SUMMARY
				,PAY_ON_USE_FLAG
				,MODE_OF_TRANSPORT
				,SERVICE_LEVEL
				,DUNS_NUMBER
				,PARTY_SITE_NAME
				,PARTY_STATUS
				,PARTY_SITE_STATUS
				,TO_CHAR(TO_DATE(SUBSTR(x.START_DATE_ACTIVE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.END_DATE_ACTIVE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  VENDOR_SITE_SPK_ID  NUMBER PATH ''./VENDOR_SITE_SPK_ID ''
										  ,VENDOR_SITE_ID NUMBER PATH ''./VENDOR_SITE_ID''
										  ,CREATION_DATE VARCHAR2(240) PATH ''./CREATION_DATE''
										  ,CREATED_BY VARCHAR2(300) PATH ''./CREATED_BY''
										  ,LAST_UPDATE_DATE VARCHAR2(240) PATH ''./LAST_UPDATE_DATE''
										  ,LAST_UPDATED_BY VARCHAR2(300) PATH ''./LAST_UPDATED_BY''
										  ,LAST_UPDATE_LOGIN VARCHAR2(300) PATH ''./LAST_UPDATE_LOGIN''
										  ,EFFECTIVE_END_DATE  VARCHAR2(240) PATH ''./EFFECTIVE_END_DATE ''
										  ,VENDOR_ID  NUMBER PATH ''./VENDOR_ID ''
										  ,OBJECT_VERSION_NUMBER NUMBER PATH ''./OBJECT_VERSION_NUMBER''
										  ,INACTIVE_DATE  VARCHAR2(240) PATH ''./INACTIVE_DATE ''
										  ,PRC_BU_ID NUMBER PATH ''./PRC_BU_ID''
										  ,LOCATION_ID NUMBER PATH ''./LOCATION_ID''
										  ,PARTY_SITE_ID NUMBER PATH ''./PARTY_SITE_ID''
										  ,VENDOR_SITE_CODE VARCHAR2(240) PATH ''./VENDOR_SITE_CODE''
										  ,PURCHASING_SITE_FLAG VARCHAR2(240) PATH ''./PURCHASING_SITE_FLAG''
										  ,RFQ_ONLY_SITE_FLAG VARCHAR2(240) PATH ''./RFQ_ONLY_SITE_FLAG''
										  ,PAY_SITE_FLAG VARCHAR2(240) PATH ''./PAY_SITE_FLAG''                        
										  ,TP_HEADER_ID NUMBER PATH ''./TP_HEADER_ID''              
										  ,TOLERANCE_ID NUMBER PATH ''./TOLERANCE_ID''                           
										  ,TERMS_ID NUMBER PATH ''./TERMS_ID''                           
										  ,EXCLUDE_FREIGHT_FROM_DISCOUNT VARCHAR2(240) PATH ''./EXCLUDE_FREIGHT_FROM_DISCOUNT''                           
										  ,BANK_CHARGE_BEARER VARCHAR2(240) PATH ''./BANK_CHARGE_BEARER''                           
										  ,PAY_ON_CODE VARCHAR2(240) PATH ''./PAY_ON_CODE''                           
										  ,SERVICES_TOLERANCE_ID NUMBER PATH ''./SERVICES_TOLERANCE_ID''                              
										  ,MATCH_OPTION VARCHAR2(240) PATH ''./MATCH_OPTION''           
										  ,COUNTRY_OF_ORIGIN_CODE VARCHAR2(240) PATH ''./COUNTRY_OF_ORIGIN_CODE''        
										  ,CREATE_DEBIT_MEMO_FLAG VARCHAR2(240) PATH ''./CREATE_DEBIT_MEMO_FLAG''                            
										  ,SUPPLIER_NOTIF_METHOD VARCHAR2(240) PATH ''./SUPPLIER_NOTIF_METHOD''                
										  ,EMAIL_ADDRESS VARCHAR2(240) PATH ''./EMAIL_ADDRESS''  
										  ,EFFECTIVE_START_DATE VARCHAR2(240) PATH ''./EFFECTIVE_START_DATE'' 
										  ,EFFECTIVE_SEQUENCE NUMBER PATH ''./EFFECTIVE_SEQUENCE'' 
										  ,DEFAULT_PAY_SITE_ID VARCHAR2(240) PATH ''./DEFAULT_PAY_SITE_ID'',
											PAY_ON_RECEIPT_SUMMARY_CODE VARCHAR2(240) PATH ''./PAY_ON_RECEIPT_SUMMARY_CODE'',
											ECE_TP_LOCATION_CODE VARCHAR2(240) PATH ''./ECE_TP_LOCATION_CODE'',
											PCARD_SITE_FLAG VARCHAR2(240) PATH ''./PCARD_SITE_FLAG'',
											PRIMARY_PAY_SITE_FLAG VARCHAR2(240) PATH ''./PRIMARY_PAY_SITE_FLAG'',
											SHIPPING_CONTROL VARCHAR2(240) PATH ''./SHIPPING_CONTROL'',
											SELLING_COMPANY_IDENTIFIER VARCHAR2(240) PATH ''./SELLING_COMPANY_IDENTIFIER'',
											GAPLESS_INV_NUM_FLAG VARCHAR2(240) PATH ''./GAPLESS_INV_NUM_FLAG'',
											RETAINAGE_RATE VARCHAR2(240) PATH ''./RETAINAGE_RATE'',
											AUTO_CALCULATE_INTEREST_FLAG VARCHAR2(240) PATH ''./AUTO_CALCULATE_INTEREST_FLAG'',
											HOLD_BY VARCHAR2(240) PATH ''./HOLD_BY'',
											HOLD_DATE VARCHAR2(240) PATH ''./HOLD_DATE'',
											HOLD_FLAG VARCHAR2(240) PATH ''./HOLD_FLAG'',
											PURCHASING_HOLD_REASON VARCHAR2(240) PATH ''./PURCHASING_HOLD_REASON'',
											VENDOR_SITE_CODE_ALT VARCHAR2(240) PATH ''./VENDOR_SITE_CODE_ALT'',
											ATTENTION_AR_FLAG VARCHAR2(240) PATH ''./ATTENTION_AR_FLAG'',
											AREA_CODE VARCHAR2(240) PATH ''./AREA_CODE'',
											PHONE VARCHAR2(240) PATH ''./PHONE'',
											CUSTOMER_NUM VARCHAR2(240) PATH ''./CUSTOMER_NUM'',
											SHIP_VIA_LOOKUP_CODE VARCHAR2(240) PATH ''./SHIP_VIA_LOOKUP_CODE'',
											FREIGHT_TERMS_LOOKUP_CODE VARCHAR2(240) PATH ''./FREIGHT_TERMS_LOOKUP_CODE'',
											FOB_LOOKUP_CODE VARCHAR2(240) PATH ''./FOB_LOOKUP_CODE'',
											FAX VARCHAR2(240) PATH ''./FAX'',
											FAX_AREA_CODE VARCHAR2(240) PATH ''./FAX_AREA_CODE'',
											TELEX VARCHAR2(240) PATH ''./TELEX'',
											TERMS_DATE_BASIS VARCHAR2(240) PATH ''./TERMS_DATE_BASIS'',
											PAY_GROUP_LOOKUP_CODE VARCHAR2(240) PATH ''./PAY_GROUP_LOOKUP_CODE'',
											PAYMENT_PRIORITY NUMBER PATH ''./PAYMENT_PRIORITY'',
											INVOICE_AMOUNT_LIMIT NUMBER PATH ''./INVOICE_AMOUNT_LIMIT'',
											PAY_DATE_BASIS_LOOKUP_CODE VARCHAR2(240) PATH ''./PAY_DATE_BASIS_LOOKUP_CODE'',
											ALWAYS_TAKE_DISC_FLAG VARCHAR2(240) PATH ''./ALWAYS_TAKE_DISC_FLAG'',
											INVOICE_CURRENCY_CODE VARCHAR2(240) PATH ''./INVOICE_CURRENCY_CODE'',
											PAYMENT_CURRENCY_CODE VARCHAR2(240) PATH ''./PAYMENT_CURRENCY_CODE'',
											HOLD_ALL_PAYMENTS_FLAG VARCHAR2(240) PATH ''./HOLD_ALL_PAYMENTS_FLAG'',
											HOLD_FUTURE_PAYMENTS_FLAG VARCHAR2(240) PATH ''./HOLD_FUTURE_PAYMENTS_FLAG'',
											HOLD_REASON VARCHAR2(240) PATH ''./HOLD_REASON'',
											HOLD_UNMATCHED_INVOICES_FLAG VARCHAR2(240) PATH ''./HOLD_UNMATCHED_INVOICES_FLAG'',
											PAYMENT_HOLD_DATE VARCHAR2(240) PATH ''./PAYMENT_HOLD_DATE'',
											TAX_REPORTING_SITE_FLAG VARCHAR2(240) PATH ''./TAX_REPORTING_SITE_FLAG'',
											REQUEST_ID NUMBER PATH ''./REQUEST_ID'',
											PROGRAM_APPLICATION_ID NUMBER PATH ''./PROGRAM_APPLICATION_ID'',
											PROGRAM_ID NUMBER PATH ''./PROGRAM_ID'',
											PROGRAM_UPDATE_DATE VARCHAR2(240) PATH ''./PROGRAM_UPDATE_DATE'',
											GLOBAL_ATTRIBUTE_CATEGORY VARCHAR2(240) PATH ''./GLOBAL_ATTRIBUTE_CATEGORY'',
											CARRIER_ID NUMBER PATH ''./CARRIER_ID'',
											ALLOW_SUBSTITUTE_RECEIPTS_FLAG VARCHAR2(240) PATH ''./ALLOW_SUBSTITUTE_RECEIPTS_FLAG'',
											ALLOW_UNORDERED_RECEIPTS_FLAG VARCHAR2(240) PATH ''./ALLOW_UNORDERED_RECEIPTS_FLAG'',
											ENFORCE_SHIP_TO_LOCATION_CODE VARCHAR2(240) PATH ''./ENFORCE_SHIP_TO_LOCATION_CODE'',
											QTY_RCV_EXCEPTION_CODE VARCHAR2(240) PATH ''./QTY_RCV_EXCEPTION_CODE'',
											RECEIPT_DAYS_EXCEPTION_CODE VARCHAR2(240) PATH ''./RECEIPT_DAYS_EXCEPTION_CODE'',
											INSPECTION_REQUIRED_FLAG VARCHAR2(240) PATH ''./INSPECTION_REQUIRED_FLAG'',
											RECEIPT_REQUIRED_FLAG VARCHAR2(240) PATH ''./RECEIPT_REQUIRED_FLAG'',
											QTY_RCV_TOLERANCE NUMBER PATH ''./QTY_RCV_TOLERANCE'',
											DAYS_EARLY_RECEIPT_ALLOWED NUMBER PATH ''./DAYS_EARLY_RECEIPT_ALLOWED'',
											DAYS_LATE_RECEIPT_ALLOWED NUMBER PATH ''./DAYS_LATE_RECEIPT_ALLOWED'',
											RECEIVING_ROUTING_ID NUMBER PATH ''./RECEIVING_ROUTING_ID'',
											SHIPPING_NETWORK_LOCATION VARCHAR2(240) PATH ''./SHIPPING_NETWORK_LOCATION'',
											FAX_COUNTRY_CODE VARCHAR2(240) PATH ''./FAX_COUNTRY_CODE'',
											TAX_COUNTRY_CODE VARCHAR2(240) PATH ''./TAX_COUNTRY_CODE'',
											AGING_PERIOD_DAYS VARCHAR2(240) PATH ''./AGING_PERIOD_DAYS'',
											AGING_ONSET_POINT VARCHAR2(240) PATH ''./AGING_ONSET_POINT'',
											CONSUMPTION_ADVICE_FREQUENCY VARCHAR2(240) PATH ''./CONSUMPTION_ADVICE_FREQUENCY'',
											CONSUMPTION_ADVICE_SUMMARY VARCHAR2(240) PATH ''./CONSUMPTION_ADVICE_SUMMARY'',
											PAY_ON_USE_FLAG VARCHAR2(240) PATH ''./PAY_ON_USE_FLAG'',
											MODE_OF_TRANSPORT VARCHAR2(240) PATH ''./MODE_OF_TRANSPORT'',
											SERVICE_LEVEL VARCHAR2(240) PATH ''./SERVICE_LEVEL'',
											DUNS_NUMBER VARCHAR2(240) PATH ''./DUNS_NUMBER'',
											PARTY_SITE_NAME VARCHAR2(240) PATH ''./PARTY_SITE_NAME'',
											PARTY_STATUS VARCHAR2(240) PATH ''./PARTY_STATUS'',
											PARTY_SITE_STATUS VARCHAR2(240) PATH ''./PARTY_SITE_STATUS'',
											START_DATE_ACTIVE VARCHAR2(240) PATH ''./START_DATE_ACTIVE'',
											END_DATE_ACTIVE VARCHAR2(240) PATH ''./END_DATE_ACTIVE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_POZ_SUPPLIER_SITES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_POZ_SUPPLIER_SITES_V  L WHERE L.VENDOR_SITE_SPK_ID  = x.VENDOR_SITE_SPK_ID )' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_poz_supplier_sites_v
            SET
                vendor_site_spk_id = agis_lookup_xml_data_rec.vendor_site_spk_id,
                vendor_site_id = agis_lookup_xml_data_rec.vendor_site_id,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                created_by = agis_lookup_xml_data_rec.created_by,
                last_update_date = agis_lookup_xml_data_rec.last_update_date,
                last_updated_by = agis_lookup_xml_data_rec.last_updated_by,
                last_update_login = agis_lookup_xml_data_rec.last_update_login,
                effective_end_date = agis_lookup_xml_data_rec.effective_end_date,
                vendor_id = agis_lookup_xml_data_rec.vendor_id,
                object_version_number = agis_lookup_xml_data_rec.object_version_number,
                inactive_date = agis_lookup_xml_data_rec.inactive_date,
                prc_bu_id = agis_lookup_xml_data_rec.prc_bu_id,
                location_id = agis_lookup_xml_data_rec.location_id,
                party_site_id = agis_lookup_xml_data_rec.party_site_id,
                vendor_site_code = agis_lookup_xml_data_rec.vendor_site_code,
                purchasing_site_flag = agis_lookup_xml_data_rec.purchasing_site_flag,
                rfq_only_site_flag = agis_lookup_xml_data_rec.rfq_only_site_flag,
                pay_site_flag = agis_lookup_xml_data_rec.pay_site_flag,
                tp_header_id = agis_lookup_xml_data_rec.tp_header_id,
                tolerance_id = agis_lookup_xml_data_rec.tolerance_id,
                terms_id = agis_lookup_xml_data_rec.terms_id,
                exclude_freight_from_discount = agis_lookup_xml_data_rec.exclude_freight_from_discount,
                bank_charge_bearer = agis_lookup_xml_data_rec.bank_charge_bearer,
                pay_on_code = agis_lookup_xml_data_rec.pay_on_code,
                services_tolerance_id = agis_lookup_xml_data_rec.services_tolerance_id,
                match_option = agis_lookup_xml_data_rec.match_option,
                country_of_origin_code = agis_lookup_xml_data_rec.country_of_origin_code,
                create_debit_memo_flag = agis_lookup_xml_data_rec.create_debit_memo_flag,
                supplier_notif_method = agis_lookup_xml_data_rec.supplier_notif_method,
                email_address = agis_lookup_xml_data_rec.email_address,
                effective_start_date = agis_lookup_xml_data_rec.effective_start_date,
                effective_sequence = agis_lookup_xml_data_rec.effective_sequence,
                default_pay_site_id = agis_lookup_xml_data_rec.default_pay_site_id,
                pay_on_receipt_summary_code = agis_lookup_xml_data_rec.pay_on_receipt_summary_code,
                ece_tp_location_code = agis_lookup_xml_data_rec.ece_tp_location_code,
                pcard_site_flag = agis_lookup_xml_data_rec.pcard_site_flag,
                primary_pay_site_flag = agis_lookup_xml_data_rec.primary_pay_site_flag,
                shipping_control = agis_lookup_xml_data_rec.shipping_control,
                selling_company_identifier = agis_lookup_xml_data_rec.selling_company_identifier,
                gapless_inv_num_flag = agis_lookup_xml_data_rec.gapless_inv_num_flag,
                retainage_rate = agis_lookup_xml_data_rec.retainage_rate,
                auto_calculate_interest_flag = agis_lookup_xml_data_rec.auto_calculate_interest_flag,
                hold_by = agis_lookup_xml_data_rec.hold_by,
                hold_date = agis_lookup_xml_data_rec.hold_date,
                hold_flag = agis_lookup_xml_data_rec.hold_flag,
                purchasing_hold_reason = agis_lookup_xml_data_rec.purchasing_hold_reason,
                vendor_site_code_alt = agis_lookup_xml_data_rec.vendor_site_code_alt,
                attention_ar_flag = agis_lookup_xml_data_rec.attention_ar_flag,
                area_code = agis_lookup_xml_data_rec.area_code,
                phone = agis_lookup_xml_data_rec.phone,
                customer_num = agis_lookup_xml_data_rec.customer_num,
                ship_via_lookup_code = agis_lookup_xml_data_rec.ship_via_lookup_code,
                freight_terms_lookup_code = agis_lookup_xml_data_rec.freight_terms_lookup_code,
                fob_lookup_code = agis_lookup_xml_data_rec.fob_lookup_code,
                fax = agis_lookup_xml_data_rec.fax,
                fax_area_code = agis_lookup_xml_data_rec.fax_area_code,
                telex = agis_lookup_xml_data_rec.telex,
                terms_date_basis = agis_lookup_xml_data_rec.terms_date_basis,
                pay_group_lookup_code = agis_lookup_xml_data_rec.pay_group_lookup_code,
                payment_priority = agis_lookup_xml_data_rec.payment_priority,
                invoice_amount_limit = agis_lookup_xml_data_rec.invoice_amount_limit,
                pay_date_basis_lookup_code = agis_lookup_xml_data_rec.pay_date_basis_lookup_code,
                always_take_disc_flag = agis_lookup_xml_data_rec.always_take_disc_flag,
                invoice_currency_code = agis_lookup_xml_data_rec.invoice_currency_code,
                payment_currency_code = agis_lookup_xml_data_rec.payment_currency_code,
                hold_all_payments_flag = agis_lookup_xml_data_rec.hold_all_payments_flag,
                hold_future_payments_flag = agis_lookup_xml_data_rec.hold_future_payments_flag,
                hold_reason = agis_lookup_xml_data_rec.hold_reason,
                hold_unmatched_invoices_flag = agis_lookup_xml_data_rec.hold_unmatched_invoices_flag,
                payment_hold_date = agis_lookup_xml_data_rec.payment_hold_date,
                tax_reporting_site_flag = agis_lookup_xml_data_rec.tax_reporting_site_flag,
                request_id = agis_lookup_xml_data_rec.request_id,
                program_application_id = agis_lookup_xml_data_rec.program_application_id,
                program_id = agis_lookup_xml_data_rec.program_id,
                program_update_date = agis_lookup_xml_data_rec.program_update_date,
                global_attribute_category = agis_lookup_xml_data_rec.global_attribute_category,
                carrier_id = agis_lookup_xml_data_rec.carrier_id,
                allow_substitute_receipts_flag = agis_lookup_xml_data_rec.allow_substitute_receipts_flag,
                allow_unordered_receipts_flag = agis_lookup_xml_data_rec.allow_unordered_receipts_flag,
                enforce_ship_to_location_code = agis_lookup_xml_data_rec.enforce_ship_to_location_code,
                qty_rcv_exception_code = agis_lookup_xml_data_rec.qty_rcv_exception_code,
                receipt_days_exception_code = agis_lookup_xml_data_rec.receipt_days_exception_code,
                inspection_required_flag = agis_lookup_xml_data_rec.inspection_required_flag,
                receipt_required_flag = agis_lookup_xml_data_rec.receipt_required_flag,
                qty_rcv_tolerance = agis_lookup_xml_data_rec.qty_rcv_tolerance,
                days_early_receipt_allowed = agis_lookup_xml_data_rec.days_early_receipt_allowed,
                days_late_receipt_allowed = agis_lookup_xml_data_rec.days_late_receipt_allowed,
                receiving_routing_id = agis_lookup_xml_data_rec.receiving_routing_id,
                shipping_network_location = agis_lookup_xml_data_rec.shipping_network_location,
                fax_country_code = agis_lookup_xml_data_rec.fax_country_code,
                tax_country_code = agis_lookup_xml_data_rec.tax_country_code,
                aging_period_days = agis_lookup_xml_data_rec.aging_period_days,
                aging_onset_point = agis_lookup_xml_data_rec.aging_onset_point,
                consumption_advice_frequency = agis_lookup_xml_data_rec.consumption_advice_frequency,
                consumption_advice_summary = agis_lookup_xml_data_rec.consumption_advice_summary,
                pay_on_use_flag = agis_lookup_xml_data_rec.pay_on_use_flag,
                mode_of_transport = agis_lookup_xml_data_rec.mode_of_transport,
                service_level = agis_lookup_xml_data_rec.service_level,
                duns_number = agis_lookup_xml_data_rec.duns_number,
                party_site_name = agis_lookup_xml_data_rec.party_site_name,
                party_status = agis_lookup_xml_data_rec.party_status,
                party_site_status = agis_lookup_xml_data_rec.party_site_status,
                start_date_active = agis_lookup_xml_data_rec.start_date_active,
                end_date_active = agis_lookup_xml_data_rec.end_date_active
            WHERE      --define the primary keys
                vendor_site_spk_id = agis_lookup_xml_data_rec.vendor_site_spk_id;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_poz_supplier_sites_v (
            vendor_site_spk_id,
            vendor_site_id,
            creation_date,
            created_by,
            last_update_date,
            last_updated_by,
            last_update_login,
            effective_end_date,
            vendor_id,
            object_version_number,
            inactive_date,
            prc_bu_id,
            location_id,
            party_site_id,
            vendor_site_code,
            purchasing_site_flag,
            rfq_only_site_flag,
            pay_site_flag,
            tp_header_id,
            tolerance_id,
            terms_id,
            exclude_freight_from_discount,
            bank_charge_bearer,
            pay_on_code,
            services_tolerance_id,
            match_option,
            country_of_origin_code,
            create_debit_memo_flag,
            supplier_notif_method,
            email_address,
            effective_start_date,
            effective_sequence,
            default_pay_site_id,
            pay_on_receipt_summary_code,
            ece_tp_location_code,
            pcard_site_flag,
            primary_pay_site_flag,
            shipping_control,
            selling_company_identifier,
            gapless_inv_num_flag,
            retainage_rate,
            auto_calculate_interest_flag,
            hold_by,
            hold_date,
            hold_flag,
            purchasing_hold_reason,
            vendor_site_code_alt,
            attention_ar_flag,
            area_code,
            phone,
            customer_num,
            ship_via_lookup_code,
            freight_terms_lookup_code,
            fob_lookup_code,
            fax,
            fax_area_code,
            telex,
            terms_date_basis,
            pay_group_lookup_code,
            payment_priority,
            invoice_amount_limit,
            pay_date_basis_lookup_code,
            always_take_disc_flag,
            invoice_currency_code,
            payment_currency_code,
            hold_all_payments_flag,
            hold_future_payments_flag,
            hold_reason,
            hold_unmatched_invoices_flag,
            payment_hold_date,
            tax_reporting_site_flag,
            request_id,
            program_application_id,
            program_id,
            program_update_date,
            global_attribute_category,
            carrier_id,
            allow_substitute_receipts_flag,
            allow_unordered_receipts_flag,
            enforce_ship_to_location_code,
            qty_rcv_exception_code,
            receipt_days_exception_code,
            inspection_required_flag,
            receipt_required_flag,
            qty_rcv_tolerance,
            days_early_receipt_allowed,
            days_late_receipt_allowed,
            receiving_routing_id,
            shipping_network_location,
            fax_country_code,
            tax_country_code,
            aging_period_days,
            aging_onset_point,
            consumption_advice_frequency,
            consumption_advice_summary,
            pay_on_use_flag,
            mode_of_transport,
            service_level,
            duns_number,
            party_site_name,
            party_status,
            party_site_status,
            start_date_active,
            end_date_active
        )
            ( SELECT
                x.vendor_site_spk_id,
                x.vendor_site_id,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.created_by,
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.last_updated_by,
                x.last_update_login,
                to_char(to_date(substr(x.effective_end_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.vendor_id,
                x.object_version_number,
                to_char(to_date(substr(x.inactive_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.prc_bu_id,
                x.location_id,
                x.party_site_id,
                x.vendor_site_code,
                x.purchasing_site_flag,
                x.rfq_only_site_flag,
                x.pay_site_flag,
                x.tp_header_id,
                x.tolerance_id,
                x.terms_id,
                x.exclude_freight_from_discount,
                x.bank_charge_bearer,
                x.pay_on_code,
                x.services_tolerance_id,
                x.match_option,
                x.country_of_origin_code,
                x.create_debit_memo_flag,
                x.supplier_notif_method,
                x.email_address,
                to_char(to_date(substr(x.effective_start_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                x.effective_sequence,
                default_pay_site_id,
                pay_on_receipt_summary_code,
                ece_tp_location_code,
                pcard_site_flag,
                primary_pay_site_flag,
                shipping_control,
                selling_company_identifier,
                gapless_inv_num_flag,
                retainage_rate,
                auto_calculate_interest_flag,
                hold_by,
                to_char(to_date(substr(x.hold_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                hold_flag,
                purchasing_hold_reason,
                vendor_site_code_alt,
                attention_ar_flag,
                area_code,
                phone,
                customer_num,
                ship_via_lookup_code,
                freight_terms_lookup_code,
                fob_lookup_code,
                fax,
                fax_area_code,
                telex,
                terms_date_basis,
                pay_group_lookup_code,
                payment_priority,
                invoice_amount_limit,
                pay_date_basis_lookup_code,
                always_take_disc_flag,
                invoice_currency_code,
                payment_currency_code,
                hold_all_payments_flag,
                hold_future_payments_flag,
                hold_reason,
                hold_unmatched_invoices_flag,
                to_char(to_date(substr(x.payment_hold_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                tax_reporting_site_flag,
                request_id,
                program_application_id,
                program_id,
                to_char(to_date(substr(x.program_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                global_attribute_category,
                carrier_id,
                allow_substitute_receipts_flag,
                allow_unordered_receipts_flag,
                enforce_ship_to_location_code,
                qty_rcv_exception_code,
                receipt_days_exception_code,
                inspection_required_flag,
                receipt_required_flag,
                qty_rcv_tolerance,
                days_early_receipt_allowed,
                days_late_receipt_allowed,
                receiving_routing_id,
                shipping_network_location,
                fax_country_code,
                tax_country_code,
                to_char(to_date(substr(x.aging_period_days, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                aging_onset_point,
                consumption_advice_frequency,
                consumption_advice_summary,
                pay_on_use_flag,
                mode_of_transport,
                service_level,
                duns_number,
                party_site_name,
                party_status,
                party_site_status,
                to_char(to_date(substr(x.start_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.end_date_active, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY')
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        vendor_site_spk_id NUMBER PATH './VENDOR_SITE_SPK_ID ',
                        vendor_site_id NUMBER PATH './VENDOR_SITE_ID',
                        creation_date VARCHAR2(240) PATH './CREATION_DATE',
                        created_by VARCHAR2(300) PATH './CREATED_BY',
                        last_update_date VARCHAR2(240) PATH './LAST_UPDATE_DATE',
                        last_updated_by VARCHAR2(300) PATH './LAST_UPDATED_BY',
                        last_update_login VARCHAR2(300) PATH './LAST_UPDATE_LOGIN',
                        effective_end_date VARCHAR2(240) PATH './EFFECTIVE_END_DATE ',
                        vendor_id NUMBER PATH './VENDOR_ID ',
                        object_version_number NUMBER PATH './OBJECT_VERSION_NUMBER',
                        inactive_date VARCHAR2(240) PATH './INACTIVE_DATE ',
                        prc_bu_id NUMBER PATH './PRC_BU_ID',
                        location_id NUMBER PATH './LOCATION_ID',
                        party_site_id NUMBER PATH './PARTY_SITE_ID',
                        vendor_site_code VARCHAR2(240) PATH './VENDOR_SITE_CODE',
                        purchasing_site_flag VARCHAR2(240) PATH './PURCHASING_SITE_FLAG',
                        rfq_only_site_flag VARCHAR2(240) PATH './RFQ_ONLY_SITE_FLAG',
                        pay_site_flag VARCHAR2(240) PATH './PAY_SITE_FLAG',
                        tp_header_id NUMBER PATH './TP_HEADER_ID',
                        tolerance_id NUMBER PATH './TOLERANCE_ID',
                        terms_id NUMBER PATH './TERMS_ID',
                        exclude_freight_from_discount VARCHAR2(240) PATH './EXCLUDE_FREIGHT_FROM_DISCOUNT',
                        bank_charge_bearer VARCHAR2(240) PATH './BANK_CHARGE_BEARER',
                        pay_on_code VARCHAR2(240) PATH './PAY_ON_CODE',
                        services_tolerance_id NUMBER PATH './SERVICES_TOLERANCE_ID',
                        match_option VARCHAR2(240) PATH './MATCH_OPTION',
                        country_of_origin_code VARCHAR2(240) PATH './COUNTRY_OF_ORIGIN_CODE',
                        create_debit_memo_flag VARCHAR2(240) PATH './CREATE_DEBIT_MEMO_FLAG',
                        supplier_notif_method VARCHAR2(240) PATH './SUPPLIER_NOTIF_METHOD',
                        email_address VARCHAR2(240) PATH './EMAIL_ADDRESS',
                        effective_start_date VARCHAR2(240) PATH './EFFECTIVE_START_DATE',
                        effective_sequence NUMBER PATH './EFFECTIVE_SEQUENCE',
                        default_pay_site_id VARCHAR2(240) PATH './DEFAULT_PAY_SITE_ID',
                        pay_on_receipt_summary_code VARCHAR2(240) PATH './PAY_ON_RECEIPT_SUMMARY_CODE',
                        ece_tp_location_code VARCHAR2(240) PATH './ECE_TP_LOCATION_CODE',
                        pcard_site_flag VARCHAR2(240) PATH './PCARD_SITE_FLAG',
                        primary_pay_site_flag VARCHAR2(240) PATH './PRIMARY_PAY_SITE_FLAG',
                        shipping_control VARCHAR2(240) PATH './SHIPPING_CONTROL',
                        selling_company_identifier VARCHAR2(240) PATH './SELLING_COMPANY_IDENTIFIER',
                        gapless_inv_num_flag VARCHAR2(240) PATH './GAPLESS_INV_NUM_FLAG',
                        retainage_rate VARCHAR2(240) PATH './RETAINAGE_RATE',
                        auto_calculate_interest_flag VARCHAR2(240) PATH './AUTO_CALCULATE_INTEREST_FLAG',
                        hold_by VARCHAR2(240) PATH './HOLD_BY',
                        hold_date VARCHAR2(240) PATH './HOLD_DATE',
                        hold_flag VARCHAR2(240) PATH './HOLD_FLAG',
                        purchasing_hold_reason VARCHAR2(240) PATH './PURCHASING_HOLD_REASON',
                        vendor_site_code_alt VARCHAR2(240) PATH './VENDOR_SITE_CODE_ALT',
                        attention_ar_flag VARCHAR2(240) PATH './ATTENTION_AR_FLAG',
                        area_code VARCHAR2(240) PATH './AREA_CODE',
                        phone VARCHAR2(240) PATH './PHONE',
                        customer_num VARCHAR2(240) PATH './CUSTOMER_NUM',
                        ship_via_lookup_code VARCHAR2(240) PATH './SHIP_VIA_LOOKUP_CODE',
                        freight_terms_lookup_code VARCHAR2(240) PATH './FREIGHT_TERMS_LOOKUP_CODE',
                        fob_lookup_code VARCHAR2(240) PATH './FOB_LOOKUP_CODE',
                        fax VARCHAR2(240) PATH './FAX',
                        fax_area_code VARCHAR2(240) PATH './FAX_AREA_CODE',
                        telex VARCHAR2(240) PATH './TELEX',
                        terms_date_basis VARCHAR2(240) PATH './TERMS_DATE_BASIS',
                        pay_group_lookup_code VARCHAR2(240) PATH './PAY_GROUP_LOOKUP_CODE',
                        payment_priority NUMBER PATH './PAYMENT_PRIORITY',
                        invoice_amount_limit NUMBER PATH './INVOICE_AMOUNT_LIMIT',
                        pay_date_basis_lookup_code VARCHAR2(240) PATH './PAY_DATE_BASIS_LOOKUP_CODE',
                        always_take_disc_flag VARCHAR2(240) PATH './ALWAYS_TAKE_DISC_FLAG',
                        invoice_currency_code VARCHAR2(240) PATH './INVOICE_CURRENCY_CODE',
                        payment_currency_code VARCHAR2(240) PATH './PAYMENT_CURRENCY_CODE',
                        hold_all_payments_flag VARCHAR2(240) PATH './HOLD_ALL_PAYMENTS_FLAG',
                        hold_future_payments_flag VARCHAR2(240) PATH './HOLD_FUTURE_PAYMENTS_FLAG',
                        hold_reason VARCHAR2(240) PATH './HOLD_REASON',
                        hold_unmatched_invoices_flag VARCHAR2(240) PATH './HOLD_UNMATCHED_INVOICES_FLAG',
                        payment_hold_date VARCHAR2(240) PATH './PAYMENT_HOLD_DATE',
                        tax_reporting_site_flag VARCHAR2(240) PATH './TAX_REPORTING_SITE_FLAG',
                        request_id NUMBER PATH './REQUEST_ID',
                        program_application_id NUMBER PATH './PROGRAM_APPLICATION_ID',
                        program_id NUMBER PATH './PROGRAM_ID',
                        program_update_date VARCHAR2(240) PATH './PROGRAM_UPDATE_DATE',
                        global_attribute_category VARCHAR2(240) PATH './GLOBAL_ATTRIBUTE_CATEGORY',
                        carrier_id NUMBER PATH './CARRIER_ID',
                        allow_substitute_receipts_flag VARCHAR2(240) PATH './ALLOW_SUBSTITUTE_RECEIPTS_FLAG',
                        allow_unordered_receipts_flag VARCHAR2(240) PATH './ALLOW_UNORDERED_RECEIPTS_FLAG',
                        enforce_ship_to_location_code VARCHAR2(240) PATH './ENFORCE_SHIP_TO_LOCATION_CODE',
                        qty_rcv_exception_code VARCHAR2(240) PATH './QTY_RCV_EXCEPTION_CODE',
                        receipt_days_exception_code VARCHAR2(240) PATH './RECEIPT_DAYS_EXCEPTION_CODE',
                        inspection_required_flag VARCHAR2(240) PATH './INSPECTION_REQUIRED_FLAG',
                        receipt_required_flag VARCHAR2(240) PATH './RECEIPT_REQUIRED_FLAG',
                        qty_rcv_tolerance NUMBER PATH './QTY_RCV_TOLERANCE',
                        days_early_receipt_allowed NUMBER PATH './DAYS_EARLY_RECEIPT_ALLOWED',
                        days_late_receipt_allowed NUMBER PATH './DAYS_LATE_RECEIPT_ALLOWED',
                        receiving_routing_id NUMBER PATH './RECEIVING_ROUTING_ID',
                        shipping_network_location VARCHAR2(240) PATH './SHIPPING_NETWORK_LOCATION',
                        fax_country_code VARCHAR2(240) PATH './FAX_COUNTRY_CODE',
                        tax_country_code VARCHAR2(240) PATH './TAX_COUNTRY_CODE',
                        aging_period_days VARCHAR2(240) PATH './AGING_PERIOD_DAYS',
                        aging_onset_point VARCHAR2(240) PATH './AGING_ONSET_POINT',
                        consumption_advice_frequency VARCHAR2(240) PATH './CONSUMPTION_ADVICE_FREQUENCY',
                        consumption_advice_summary VARCHAR2(240) PATH './CONSUMPTION_ADVICE_SUMMARY',
                        pay_on_use_flag VARCHAR2(240) PATH './PAY_ON_USE_FLAG',
                        mode_of_transport VARCHAR2(240) PATH './MODE_OF_TRANSPORT',
                        service_level VARCHAR2(240) PATH './SERVICE_LEVEL',
                        duns_number VARCHAR2(240) PATH './DUNS_NUMBER',
                        party_site_name VARCHAR2(240) PATH './PARTY_SITE_NAME',
                        party_status VARCHAR2(240) PATH './PARTY_STATUS',
                        party_site_status VARCHAR2(240) PATH './PARTY_SITE_STATUS',
                        start_date_active VARCHAR2(240) PATH './START_DATE_ACTIVE',
                        end_date_active VARCHAR2(240) PATH './END_DATE_ACTIVE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_POZ_SUPPLIER_SITES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_poz_supplier_sites_v l
                    WHERE
                        l.vendor_site_spk_id = x.vendor_site_spk_id
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_POZ_SUPPLIER_SITES_INSERT_UPDATE',
            p_tracker => 'AGIS_POZ_SUPPLIER_SITES_INSERT_UPDATE', p_custom_err_info => 'EXCEPTION3 : AGIS_POZ_SUPPLIER_SITES_INSERT_UPDATE');
    END agis_poz_supplier_sites_insert_update;

    PROCEDURE agis_error_messages_insert_update (
        p_user_name VARCHAR2
    ) IS

        TYPE agis_message_xml_data IS RECORD (
            message_name     xxagis_fnd_new_messages.message_name%TYPE,
            message_text     xxagis_fnd_new_messages.message_text%TYPE,
            description      xxagis_fnd_new_messages.description%TYPE,
            creation_date    xxagis_fnd_new_messages.creation_date%TYPE,
            last_update_date xxagis_fnd_new_messages.last_update_date%TYPE
        );
        agis_lookup_xml_data_rec agis_message_xml_data;
        lcu_read_xml_data        SYS_REFCURSOR;
    BEGIN
        dbms_output.put_line('1');
        writetolog('xxagis_utility_pkg', 'XXAGIS_ERROR_MESSAGES', 'STATEMENT', 'Procedure running for report : XXAGIS_ERROR_MESSAGES',
        'AGIS_RELATED_PARTY_HIERACHY');

	--Update
        OPEN lcu_read_xml_data FOR ( 'SELECT
				 MESSAGE_NAME
				,MESSAGE_TEXT
				,DESCRIPTION
				,TO_CHAR(TO_DATE(SUBSTR(x.CREATION_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				,TO_CHAR(TO_DATE(SUBSTR(x.LAST_UPDATE_DATE, 1, 10),''YYYY-MM-DD''),''DD-MON-YYYY'')
				FROM
					xxagis_from_base64 t,
					XMLTABLE ( ''//G_1'' PASSING xmltype(t.clobdata) COLUMNS 
										  MESSAGE_NAME VARCHAR2(100) PATH ''./MESSAGE_NAME''
										  ,MESSAGE_TEXT VARCHAR2(240) PATH ''./MESSAGE_TEXT''
										  ,DESCRIPTION VARCHAR2(1000) PATH ''./DESCRIPTION''
										  ,CREATION_DATE VARCHAR2(100) PATH ''./CREATION_DATE''
										  ,LAST_UPDATE_DATE VARCHAR2(100) PATH ''./LAST_UPDATE_DATE''
										  ) x
				WHERE t.template_name LIKE ''AGIS_ERROR_MESSAGES''
				AND t.USER_NAME= '''
                                     || p_user_name
                                     || '''
				AND  EXISTS (SELECT 1 FROM XXAGIS_FND_NEW_MESSAGES  L WHERE L.MESSAGE_NAME = x.MESSAGE_NAME)' );

        LOOP
            FETCH lcu_read_xml_data INTO agis_lookup_xml_data_rec;
            UPDATE xxagis_fnd_new_messages
            SET
                message_name = agis_lookup_xml_data_rec.message_name,
                message_text = agis_lookup_xml_data_rec.message_text,
                description = agis_lookup_xml_data_rec.description,
                creation_date = agis_lookup_xml_data_rec.creation_date,
                last_update_date = agis_lookup_xml_data_rec.last_update_date
            WHERE
                message_name = agis_lookup_xml_data_rec.message_name;

            EXIT WHEN lcu_read_xml_data%notfound;
        END LOOP;

        CLOSE lcu_read_xml_data;	

	-- Insert
        INSERT INTO xxagis_fnd_new_messages (
            message_name,
            message_text,
            description,
            creation_date,
            last_update_date
        )
            ( SELECT
                x.message_name,
                x.message_text,
                x.description,
                to_char(to_date(substr(x.creation_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY'),
                to_char(to_date(substr(x.last_update_date, 1, 10), 'YYYY-MM-DD'), 'DD-MON-YYYY')
            FROM
                xxagis_from_base64 t,
                XMLTABLE ( '//G_1'
                        PASSING xmltype(t.clobdata)
                    COLUMNS
                        message_name VARCHAR2(100) PATH './MESSAGE_NAME',
                        message_text VARCHAR2(100) PATH './MESSAGE_TEXT',
                        description VARCHAR2(100) PATH './DESCRIPTION',
                        creation_date VARCHAR2(100) PATH './CREATION_DATE',
                        last_update_date VARCHAR2(100) PATH './LAST_UPDATE_DATE'
                )                  x
            WHERE
                t.template_name LIKE 'AGIS_ERROR_MESSAGES'
                AND t.user_name = p_user_name
                AND NOT EXISTS (
                    SELECT
                        1
                    FROM
                        xxagis_fnd_new_messages l
                    WHERE
                        l.message_name = x.message_name
                )
            );

    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'AGIS_ERROR_MESSAGES_INSERT_UPDATE',
            p_tracker => 'AGIS_ERROR_MESSAGES_INSERT_UPDATE', p_custom_err_info => 'EXCEPTION3 : AGIS_ERROR_MESSAGES_INSERT_UPDATE');
    END;

    FUNCTION get_file_interface_status (
        file_id_p NUMBER
    ) RETURN VARCHAR2 IS

        CURSOR file_header IS
        SELECT
            *
        FROM
            xxagis_file_header
        WHERE
            file_id = file_id_p;

        status_o   VARCHAR2(10) := '';
        ar_count   NUMBER;
        agis_count NUMBER;
    BEGIN

        SELECT
            COUNT(*)
        INTO agis_count
        FROM
            xxagis_agis_stage
        WHERE
            file_id = file_id_p;

        SELECT
            COUNT(*)
        INTO ar_count
        FROM
            xxagis_ar_stage
        WHERE
            file_id = file_id_p;

        FOR h IN file_header LOOP
            dbms_output.put_line('INSIDE LOOP '
                                 || agis_count
                                 || ' '
                                 || ar_count);
            IF (
                agis_count > 0
                AND ar_count > 0
            ) THEN
                IF ( h.file_interface_status = 'ERROR' /*OR h.file_load_status = 'ERROR' OR h.ar_file_interface_status = 'ERROR' OR h.ar_file_load_status ='ERROR' */		/*Commented for CEN-8274_4*/
				) THEN
                    status_o := 'ERROR';
                    EXIT;
                END IF;

                IF ( h.agis_int_load_request_id IS NULL OR (
                    h.file_interface_status = 'SUCCEEDED'
                    AND h.agis_load_request_id IS NULL
                ) OR (
                    h.ar_file_interface_status = 'SUCCEEDED'
                    AND h.ar_load_request_id IS NULL
                ) OR h.ar_int_load_request_id IS NULL OR h.file_interface_status IS NULL OR h.file_load_status IS NULL OR h.ar_file_interface_status
                IS NULL OR h.ar_file_load_status IS NULL ) THEN
                    status_o := 'PROCESSING';
                    EXIT;
                END IF;

                status_o := 'SUCCESS';
                EXIT;
            END IF;

            IF (
                agis_count > 0
                AND ar_count < 1
            ) THEN

              IF ( h.file_interface_status = 'ERROR' /*CEN-8274_4*/
				/*OR h.file_interface_status <> 'SUCCEEDED'  
				  OR h.file_load_status <> 'SUCCEEDED'*/   /*Commented for CEN-8274_4*/
				  ) THEN
                    status_o := 'ERROR';
                    EXIT;
                END IF;

                IF ( h.agis_int_load_request_id IS NULL OR (
                    h.agis_int_load_request_id IS NOT NULL
                    AND h.file_interface_status IS NULL
                ) OR (
                    h.file_interface_status = 'SUCCEEDED'
                    AND h.agis_load_request_id IS NULL
                ) OR (
                    h.agis_load_request_id IS NOT NULL
                    AND h.file_load_status IS NULL
                ) ) THEN
                    status_o := 'PROCESSING';
                    EXIT;
                END IF;

                status_o := 'SUCCESS';
                EXIT;
            END IF;

            IF (
                agis_count < 1
                AND ar_count > 0
            ) THEN

			    IF (h.file_interface_status = 'ERROR' /*CEN-8274_4*/
				    /*h.ar_file_interface_status LIKE 'ERROR%' OR h.ar_file_load_status LIKE 'ERROR%'*/  /*Commented for CEN-8274_4*/
					) THEN
                    status_o := 'ERROR';
                    dbms_output.put_line('STATUS_O ' || status_o);
                    EXIT;
                END IF;

                IF ( h.ar_int_load_request_id IS NULL OR (
                    h.ar_int_load_request_id IS NOT NULL
                    AND h.ar_file_interface_status IS NULL
                ) OR (
                    h.ar_file_interface_status = 'SUCCEEDED'
                    AND h.ar_load_request_id IS NULL
                ) OR (
                    h.ar_load_request_id IS NOT NULL
                    AND h.ar_file_load_status IS NULL
                ) ) THEN
                    status_o := 'PROCESSING';
                    dbms_output.put_line('STATUS_O ' || status_o);
                    EXIT;
                END IF;

                status_o := 'SUCCESS';
                dbms_output.put_line('STATUS_O ' || status_o);
                EXIT;
            END IF;

        END LOOP;

        dbms_output.put_line('STATUS_O ' || status_o);
        RETURN status_o;
    EXCEPTION /* 3-27580827611 Exception Section */
        WHEN OTHERS THEN
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'GET_FILE_INTERFACE_STATUS', p_tracker =>
            'GET_FILE_INTERFACE_STATUS', p_custom_err_info => 'EXCEPTION3 : GET_FILE_INTERFACE_STATUS');
    END;
--CEN_8063_Start
/* Adhoc report to call the BIP Report */
/***************************************************************************
	*
	*  FUNCTION: AGIS_CALL_BIP_REPORT_ADHOC
	*
	*  Description:  Procedure used to fetch XXAGIS_soap_connection_details and sync BIP Reports into  xxagis_from_base64 table
	*
	**************************************************************************/

    PROCEDURE agis_call_bip_report_adhoc (
        p_report_name VARCHAR2,
        p_user_name   VARCHAR2,
        P_FROM_DATE   VARCHAR2,
        P_TO_DATE     VARCHAR2,
        P_FILE_ID_FROM     NUMBER,
        P_FILE_ID_TO       NUMBER
    ) AS

        CURSOR xx_get_conn_details_cur (
            p_username VARCHAR2
        ) IS
        SELECT
            *
        FROM
            xxagis_soap_connection_details
        WHERE
            source = 'ERP';

        xx_get_conn_details_rec xx_get_conn_details_cur%rowtype;
        l_envelope              CLOB;
        l_xml                   XMLTYPE;
        l_result                VARCHAR2(32767);
        l_base64                CLOB;
        l_blob                  BLOB;
        l_clob                  CLOB;
        l_http_request          utl_http.req;
        l_http_response         utl_http.resp;
        l_string_request        VARCHAR2(32000);
        buff                    VARCHAR2(32000);
        l_url                   VARCHAR2(1000);
        l_username              VARCHAR2(100);
        l_password              VARCHAR2(100);
        l_wallet_path           VARCHAR2(1000);
        l_wallet_password       VARCHAR2(100);
        l_process               VARCHAR2(1000);
        l_path                  VARCHAR2(100);
        l_tablename             VARCHAR2(100);
        l_reportname            VARCHAR2(100);
        l_parameter_name        VARCHAR2(100) := 'P_START_DATE';
        l_parameter_username    VARCHAR2(100) := 'p_user_name';
        l_parameter_value       VARCHAR2(100);
        l_proxy                 VARCHAR2(100);
    BEGIN
        gc_template := p_report_name;
        gc_user := 'PBSAdmin';--p_username;
        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker => 'BEGIN',
        p_custom_err_info => 'gc_template' || p_report_name);

        DELETE FROM xxagis_logs
        WHERE
                job_name = p_report_name
            AND creation_date <= sysdate;

        BEGIN
			------log----------
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', 'Procedure used to fetch XXAGIS_soap_connection_details and sync BIP Reports into xxagis_from_base64 table ',
            p_report_name);
			 ------------------------
            OPEN xx_get_conn_details_cur(gc_user); --p_username
			-- Fetch connection details to variables
            FETCH xx_get_conn_details_cur INTO xx_get_conn_details_rec;
            l_url := xx_get_conn_details_rec.url;
            l_username := xx_get_conn_details_rec.username;
            l_password := xx_get_conn_details_rec.password;
            l_wallet_path := xx_get_conn_details_rec.wallet_path;
            l_wallet_password := xx_get_conn_details_rec.wallet_password;
            l_proxy := xx_get_conn_details_rec.proxy_details;
				  -- close cursor
            CLOSE xx_get_conn_details_cur;
            dbms_output.put_line('l_url: ' || l_url);
            dbms_output.put_line('l_username: ' || l_username);
            dbms_output.put_line('l_wallet_path: ' || l_wallet_path);
            dbms_output.put_line('l_proxy: ' || l_proxy);
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', l_url
                                                                                  || ' '
                                                                                  || l_username
                                                                                  || ' '
                                                                                  || l_wallet_path
                                                                                  || ' '
                                                                                  || l_proxy, p_report_name);

        END;

        BEGIN
            SELECT
                decode(p_report_name, 'AGIS_LOOKUP_VALUES', 'XXAGIS_LOOKUP_VALUES', 'AGIS_VALUE_SET_VALUES', 'XXAGIS_VALUE_SET_VALUES',
                       'AGIS_GL_CALENDAR', 'GL_TRANSACTION_CALENDAR', 'AGIS_GL_DATES', 'GL_TRANSACTION_DATES', 'USER_ROLE_REPORT',
                       'XXAGIS_USER_ROLE_MAP', 'AGIS_SYSTEM_OPTIONS', 'XXAGIS_FUN_SYSTEM_OPTIONS', 'AGIS_PERIOD_STATUSES', 'XXAGIS_FUN_PERIOD_STATUSES',
                       'AGIS_GL_PERIOD_STATUSES', 'GL_PERIOD_STATUSES', 'AGIS_GL_PERIODS', 'GL_PERIODS', 'AGIS_GL_LEDGER',
                       'GL_LEDGERS', 'AGIS_INTERCO_ORGANIZATIONS', 'XXAGIS_FUN_INTERCO_ORGANIZATIONS', 'AGIS_CUSTOMER_ACCOUNT', 'XXAGIS_CUSTOMER_ACCOUNT',
                       'AGIS_CUSTOMER_PARTY_SITES', 'XXAGIS_CUSTOMER_PARTY_SITES', 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL', 'XXAGIS_CUSTOMER_ACCOUNT_SITES_ALL',
                       'AGIS_CUSTOMER_SITES_USE',
                       'XXAGIS_CUSTOMER_SITE_USE_ALL', 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', 'XXAGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', 'AGIS_RELATED_PARTY_HIERACHY',
                       'XXAGIS_RELATED_PARTY_HIERARCHY',
                       'AGIS_ERROR_MESSAGES', 'XXAGIS_FND_NEW_MESSAGES', 'AGIS_CUSTOMER_SUPPLY_MAP', 'XXAGIS_FUN_IC_CUST_SUPP_MAP', 'AGIS_POZ_SUPPLIER_SITES',
                       'XXAGIS_POZ_SUPPLIER_SITES_V',
                       --CEN_8063_Start
                       'XXAGIS_FUN_INTERFACE_HEADERS',
                       --CEN_8063_End
                       'dual')                           tablename,
                decode(p_report_name, 'AGIS_LOOKUP_VALUES', '/AGIS/Old Mutual - AGIS - Lookup Extract Report.xdo', 'AGIS_VALUE_SET_VALUES',
                '/AGIS/Old Mutual - AGIS - Value Set Extract Report.xdo',
                       'AGIS_GL_CALENDAR', '/Integration/AHCS/GL Transaction Calendar/Old Mutual - INT - GL Transaction Calendar Extract.xdo',
                       'AGIS_GL_DATES', '/Integration/AHCS/GL Transaction Date/Old Mutual - INT - GL Transaction Date Extract.xdo', 'USER_ROLE_REPORT',
                       '/AGIS/Old Mutual - AGIS - User Data Extract Report.xdo', 'AGIS_SYSTEM_OPTIONS', '/AGIS/Old Mutual - AGIS - System Options Extract Report.xdo',
                       'AGIS_PERIOD_STATUSES', '/AGIS/Old Mutual - AGIS - Period Statuses Extract Report.xdo',
                       'AGIS_GL_PERIOD_STATUSES', '/Integration/AHCS/GL Period Statuses/Old Mutual - INT - GL Period Statuses Extract.xdo',
                       'AGIS_GL_PERIODS', '/Integration/AHCS/GL Periods/Old Mutual - INT - GL Periods Extract.xdo', 'AGIS_GL_LEDGER',
                       '/Integration/AHCS/GL Ledgers Extract/Old Mutual - INT - GL Ledgers Extract.xdo', 'AGIS_INTERCO_ORGANIZATIONS',
                       '/AGIS/Old Mutual - AGIS - Interco Organizations Report.xdo', 'AGIS_CUSTOMER_ACCOUNT', '/AGIS/Old Mutual - AGIS - Customer Account Report.xdo',
                       'AGIS_CUSTOMER_PARTY_SITES', '/AGIS/Old Mutual - AGIS - Customer Party Sites Report.xdo', 'AGIS_CUSTOMER_ACCOUNT_SITES_ALL',
                       '/AGIS/Old Mutual - AGIS - Customer Account Sites All Report.xdo', 'AGIS_CUSTOMER_SITES_USE',
                       '/AGIS/Old Mutual - AGIS - Customer Account Site Use All Report.xdo', 'AGIS_CUSTOMER_ACCOUNT_SITE_PROFILE', '/AGIS/Old Mutual - AGIS - Customer Account Site Profile Report.xdo',
                       'AGIS_RELATED_PARTY_HIERACHY', '/AGIS/Old Mutual - AGIS - Related Party Hierarchy Report.xdo',
                       'AGIS_ERROR_MESSAGES', '/AGIS/Old Mutual - AGIS - Error Messages Report.xdo', 'AGIS_CUSTOMER_SUPPLY_MAP', '/AGIS/Old Mutual - AGIS - Interco Customer Supplier Map Report.xdo',
                       'AGIS_POZ_SUPPLIER_SITES',
                       '/AGIS/Old Mutual - AGIS - POZ Supplier Sites Report.xdo',
                       --CEN_8063_Start
                       'XXAGIS_FUN_INTERFACE_HEADERS' ,
                      '/AGIS/Old Mutual - AGIS - AR Invoice Number Report.xdo' ,
                      --CEN_8063_End
                       NULL) reportname
            INTO
                l_tablename,
                l_reportname
            FROM
                dual;
		---------------------------------------------------------------			

	----------------------------------------------------------------------------

        END;

        oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker => 'l_tablename',
        p_custom_err_info => 'gc_template' || p_report_name);

        IF
            l_tablename IS NOT NULL
            AND l_tablename NOT IN ( 'dual' )
            AND p_report_name NOT LIKE 'USER_ROLE_REPORT'
        THEN
            EXECUTE IMMEDIATE 'SELECT TO_CHAR(MAX(last_update_date)-1,''MM-DD-YYYY HH24:MI:SS'') FROM ' || l_tablename
            INTO l_parameter_value;
        END IF;

        IF l_parameter_value IS NULL THEN
            l_parameter_value := to_char(sysdate - 1000, 'MM-DD-YYYY HH24:MI:SS');
        END IF;

        dbms_output.put_line('l_parameter_value: ' || l_parameter_value);
        IF p_report_name LIKE 'USER_ROLE_REPORT' THEN
            l_envelope := '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">
				   <soapenv:Header/>
				   <soapenv:Body>
					  <pub:runReport>
						 <pub:reportRequest>
							<pub:attributeFormat>xml</pub:attributeFormat>
							<pub:attributeLocale>en-US</pub:attributeLocale>
							<pub:parameterNameValues>
							  <pub:item>
								<pub:name>'
                          || l_parameter_username
                          || '</pub:name>
								<pub:values>
								   <pub:item>'
                          || p_user_name
                          || '</pub:item>
								</pub:values>
							  </pub:item>
							</pub:parameterNameValues>
							<pub:reportAbsolutePath>/Custom'
                          || l_reportname
                          || '</pub:reportAbsolutePath>
							 <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>
						 </pub:reportRequest>
						 <pub:userID>'
                          || l_username
                          || '</pub:userID>
						 <pub:password>'
                          || l_password
                          || '</pub:password>
					  </pub:runReport>
				   </soapenv:Body>
				</soapenv:Envelope>';
        ELSE
            l_envelope := '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:pub="http://xmlns.oracle.com/oxp/service/PublicReportService">
				   <soapenv:Header/>
				   <soapenv:Body>
					  <pub:runReport>
						 <pub:reportRequest>
							<pub:attributeFormat>xml</pub:attributeFormat>
							<pub:attributeLocale>en-US</pub:attributeLocale>
							<pub:parameterNameValues>
                                <pub:item>
                                  <pub:name>p_date_from</pub:name>
                                  <pub:values>
                                  <pub:item>'
                          || p_from_date
                          || '</pub:item>
                                  </pub:values>
                               </pub:item>
                          <pub:item>
								  <pub:name>p_date_to</pub:name>
                                  <pub:values>
                                  <pub:item>'
                          || p_to_date
                          || '</pub:item>
                                  </pub:values>
                               </pub:item>
                               <pub:item>
								  <pub:name>p_file_id_from</pub:name>
                                  <pub:values>
                                  <pub:item>'
                          || p_file_id_from
                          || '</pub:item>
                                  </pub:values>
                               </pub:item>
                               <pub:item>
								  <pub:name>p_file_id_to</pub:name>
                                  <pub:values>
                                  <pub:item>'
                          || p_file_id_to
                          || '</pub:item>
                                  </pub:values>
                               </pub:item>
							  <pub:item>
								<pub:name>'
                          || l_parameter_name
                          || '</pub:name>
								<pub:values>
								   <pub:item>'
                          || l_parameter_value
                          || '</pub:item>
								</pub:values>
							  </pub:item>
							</pub:parameterNameValues>
							<pub:reportAbsolutePath>/Custom'
                          || l_reportname
                          || '</pub:reportAbsolutePath>
							  <pub:sizeOfDataChunkDownload>-1</pub:sizeOfDataChunkDownload>
						 </pub:reportRequest>
						 <pub:userID>'
                          || l_username
                          || '</pub:userID>
						 <pub:password>'
                          || l_password
                          || '</pub:password>
					  </pub:runReport>
				   </soapenv:Body>
				</soapenv:Envelope>';
        END IF;

        IF ( l_proxy IS NOT NULL ) THEN
            utl_http.set_proxy(l_proxy);
        END IF;
        BEGIN
				--dbms_output.put_line('l_envelope: ' || l_envelope);
            BEGIN
                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', substr(l_envelope, 1, 1000), p_report_name || ' Payload');

                l_xml := apex_web_service.make_request(p_url => l_url || '/xmlpserver/services/PublicReportService', p_envelope => l_envelope,
                p_wallet_path => l_wallet_path, p_wallet_pwd => l_wallet_password);

            EXCEPTION
                WHEN OTHERS THEN
                    writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', sqlerrm, 'Error at apex_web_service.make_request');
            END;

            BEGIN
                l_base64 := apex_web_service.parse_xml_clob(p_xml => l_xml, p_xpath => '//reportBytes/text()', p_ns => 'xmlns="http://xmlns.oracle.com/oxp/service/PublicReportService"');

                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', substr(l_xml.getstringval(), 1, 1000), p_report_name ||
                ' l_base64');

            EXCEPTION
                WHEN OTHERS THEN
                    writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'Error at apex_web_service.parse_xml_clob', sqlerrm);
					/* 3-27580827611 Exception Section */
                    oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker =>
                    'agis_call_bip_report', p_custom_err_info => 'Error at apex_web_service.parse_xml_clob');

            END;

	--            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'l_base64 '||substr(l_base64,1000), p_report_name);

            base64_decode(l_base64, l_clob);
            dbms_output.put_line('l_clob received ');
            IF dbms_lob.getlength(l_clob) > 0 THEN
                BEGIN
                    DELETE FROM xxagis_from_base64
                    WHERE
                            template_name = p_report_name
                        AND user_name = p_user_name;

                    INSERT INTO xxagis_from_base64 (
                        loadtime,
                        clobdata,
                        created_by,
                        creation_date,
                        last_update_date,
                        last_updated_by,
                        last_update_login,
                        template_name,
                        user_name
                    ) VALUES (
                        sysdate,
                        l_clob,
                        gc_user,
                        sysdate,
                        sysdate,
                        gc_user,
                        gc_user,
                        p_report_name,
                        p_user_name
                    );

                    agis_insert_data(p_report_name, p_user_name);
                    COMMIT;
                END;
            ELSE
                writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'STATEMENT', 'BIP RETURNED NO RECORDS '
                                                                                      || 'PARAM N: '
                                                                                      || l_parameter_value
                                                                                      || ' V:'
                                                                                      || l_parameter_name, p_report_name);
            END IF;

        END;

    EXCEPTION
        WHEN OTHERS THEN
            writetolog('xxagis_utility_pkg', 'agis_call_bip_report', 'ERROR', 'Error '
                                                                              || substr(sqlerrm, 1, 1000), 'agis_call_bip_report ');
           /* 3-27580827611 Exception Section */
            oml_format_error_logs_pkg.log_error(p_module => 'xxagis_utility_pkg', p_sub_module => 'agis_call_bip_report', p_tracker =>
            'agis_call_bip_report', p_custom_err_info => 'Error '
                                                                                                                                    ||
                                                                                                                                    substr(
                                                                                                                                    sqlerrm,
                                                                                                                                    1,
                                                                                                                                    1000));

    END;

 --CEN_8063_start
    	/***************************************************************************
	*
	*  PROCEDURE: agis_original_invoice_update
	*
	*  Description:  Syncs Agis Invoice Number BIP Report into XXAGIS_FUN_INTERFACE_HEADERS table
	*
	**************************************************************************/
    PROCEDURE agis_original_invoice_update (
        p_user_name VARCHAR2
    ) AS

        TYPE agis_invoice_xml_data IS RECORD (
                batch_id          xxagis_fun_interface_batches.attribute1%TYPE,
                file_id           xxagis_fun_interface_batches.attribute2%TYPE,
                status            xxagis_fun_interface_headers.attribute13%TYPE,  
             --CEN-12837_Start
                INCOME_BUDGET_CENTER xxagis_fun_interface_headers.attribute1%TYPE,
                EXPENSE_BUDGET_CENTER xxagis_fun_interface_headers.attribute2%TYPE,
                CHARGE_CATEGORY xxagis_fun_interface_headers.attribute3%TYPE,
                AMOUNT xxagis_fun_interface_headers.INIT_AMOUNT_DR%TYPE,
                DESCRIPTION xxagis_fun_interface_headers.DESCRIPTION%TYPE,
             --CEN-12837_End
                ar_invoice_number xxagis_fun_interface_headers.trx_number%TYPE,
                --CEN_12951_Start
                TRX_NUMBER  xxagis_fun_interface_headers.trx_number%TYPE
                --CEN_12951_End 
        );
        agis_original_invoice_xml_data_rec agis_invoice_xml_data;
        lcu_read_xml_data                  SYS_REFCURSOR;
    BEGIN
     	-------------------------------------
        writetolog('xxagis_utility_pkg', 'agis_original_invoice_update', 'STATEMENT', 'Procedure running for report name: XXAGIS_FUN_INTERFACE_HEADERS'
        , 'XXAGIS_FUN_INTERFACE_HEADERS');
	----------------------------------------------- 
	--update
OPEN lcu_read_xml_data FOR ( 'SELECT
    BATCH_ID,
    FILE_ID,
    STATUS ,
    --CEN-12837_Start  
    INCOME_BUDGET_CENTER ,
    EXPENSE_BUDGET_CENTER ,
    CHARGE_CATEGORY ,
    AMOUNT ,
    DESCRIPTION ,
    --CEN-12837_End
    AR_INVOICE_NUMBER,
    --CEN_12951_Start
    TRX_NUMBER
    --CEN_12951_End
    FROM
    xxagis_from_base64 t,
       XMLTABLE ( ''//G_1''
        PASSING xmltype(t.clobdata)
    COLUMNS
                batch_id VARCHAR2(240) PATH ''./BATCH_ID'',
                FILE_ID VARCHAR2(240) PATH ''./FILE_ID'',
                STATUS VARCHAR2(240) PATH ''./STATUS'',
                --CEN_12951_Start
                TRX_NUMBER VARCHAR2(240) PATH ''./TRX_NUMBER'',
                --CEN_12951_End
                --CEN-12837_Start
                INCOME_BUDGET_CENTER VARCHAR2(240) PATH ''./INCOME_BUDGET_CENTER'',
                EXPENSE_BUDGET_CENTER VARCHAR2(240) PATH ''./EXPENSE_BUDGET_CENTER'',
                CHARGE_CATEGORY VARCHAR2(240) PATH ''./CHARGE_CATEGORY'',
                AMOUNT VARCHAR2(240) PATH ''./AMOUNT'',
                DESCRIPTION VARCHAR2(240) PATH ''./DESCRIPTION'',
                --CEN-12837_End
                AR_INVOICE_NUMBER VARCHAR2(240) PATH ''./AR_INVOICE_NUMBER'') X  
   WHERE TEMPLATE_NAME =''XXAGIS_FUN_INTERFACE_HEADERS''
   AND t.user_name = '''
                                     || p_user_name
                                     || '''
AND 
EXISTS (SELECT 1 FROM XXAGIS_FUN_INTERFACE_HEADERS L WHERE L.BATCH_ID = x.batch_id
OR EXISTS (select 1 from XXAGIS_RA_INTERFACE_LINES_ALL where INTERFACE_LINE_ATTRIBUTE3 = x.batch_id)
)
' );
        LOOP
            FETCH lcu_read_xml_data INTO agis_original_invoice_xml_data_rec;
            UPDATE xxagis_fun_interface_headers
            SET
                attribute14 = agis_original_invoice_xml_data_rec.ar_invoice_number,
                attribute13 = agis_original_invoice_xml_data_rec.status  
            WHERE
                batch_id = agis_original_invoice_xml_data_rec.batch_id
            --CEN-12837_Start    
			-- In this stage only Successfull transactions flow PAAS to SAAS.
			-- So only successful transactions will update original Invoice Numbers from SAAS to PAAS
			-- excluded project code because Project code concatinate with the Descritption
             AND ATTRIBUTE1 = agis_original_invoice_xml_data_rec.INCOME_BUDGET_CENTER
             AND ATTRIBUTE2    = agis_original_invoice_xml_data_rec.EXPENSE_BUDGET_CENTER
             AND ATTRIBUTE3    = agis_original_invoice_xml_data_rec.CHARGE_CATEGORY
             AND INIT_AMOUNT_DR= agis_original_invoice_xml_data_rec.AMOUNT
             --CEN-12837_End
             --CEN_12951_Start

           -- AND DESCRIPTION  = agis_original_invoice_xml_data_rec.DESCRIPTION -- COMMENTED FOR THE SPECIAL CHARACTERS
             AND TRX_NUMBER = agis_original_invoice_xml_data_rec.TRX_NUMBER
             --CEN_12951_End
             ;
            UPDATE xxagis_ra_interface_lines_all
            SET
                attribute14 = agis_original_invoice_xml_data_rec.ar_invoice_number
            WHERE
                    interface_line_attribute3 = agis_original_invoice_xml_data_rec.batch_id
                    --CEN_12951_Start
                AND   INTERFACE_LINE_ATTRIBUTE4 =agis_original_invoice_xml_data_rec.TRX_NUMBER
                    --CEN_12951_End
                AND file_id = agis_original_invoice_xml_data_rec.file_id;
            COMMIT;
            EXIT WHEN lcu_read_xml_data%notfound;

        END LOOP;

        CLOSE lcu_read_xml_data;
    END agis_original_invoice_update;
    --CEN_8063_End
END xxagis_utility_pkg;