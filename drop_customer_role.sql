CREATE OR REPLACE FUNCTION drop_customer_role()
RETURNS VOID 
LANGUAGE plpgsql
AS
$$
DECLARE
    customer_record     RECORD;
    role_name           TEXT;
    email_password      TEXT;
BEGIN
    FOR customer_record IN (
                            SELECT 
                                c.customer_id,
                                c.first_name,
                                c.last_name,
                                c.email
                            FROM 
                                customer c
                            WHERE 
                                c.customer_id IN (SELECT DISTINCT customer_id FROM payment) AND
                                c.customer_id IN (SELECT DISTINCT customer_id FROM rental)
                            ORDER BY
                                c.customer_id ASC    
                           )
    LOOP
        -- assign role_name variable and remove spaces from first_name and last_name
        role_name := lower('client_' || REPLACE(customer_record.first_name, ' ', '') || '_' || REPLACE(customer_record.last_name, ' ', ''));
        -- depending on how the users were created you may need to change the previous line to the following:
	-- role_name := 'client_' || UPPER(REPLACE(customer_record.first_name, ' ', '') || '_' || REPLACE(customer_record.last_name, ' ', ''));
    
        -- Check if the role_name already exists
        PERFORM 1 FROM pg_roles WHERE rolname = role_name;
        
        IF FOUND THEN
            -- Role found, delete it
            RAISE NOTICE 'USER ''%'' is dropping...', role_name;
            EXECUTE 'REASSIGN OWNED BY ' || quote_ident(role_name) || ' TO postgres';
            EXECUTE 'DROP OWNED BY ' || quote_ident(role_name);
            EXECUTE 'DROP USER ' || quote_ident(role_name);
        ELSE
            RAISE NOTICE 'USER ''%'' has already dropped. Nothing to do.', role_name;
        END IF
        ;
    END LOOP
    ;
END
;
$$
;
