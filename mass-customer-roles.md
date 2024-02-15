# How to create and remove hundreds of users in the dvdrental database (Sakila) and how to solve the issue with the database drop: ERROR:  wrong tuple length
## Starting from the back: how to remove hundreds users from the database quickly
Recently I have faced with a not typical issue - my database used for learning process (***Sakila DVD Rental database***) - was not deletable. Any attempts to drop it were totally unsuccessful. 
I tried to do it via DBeaver and via pgAdmin (in the context menu *Delete* or *Delete (Force)*, but always got the same error message: 
```
DROP DATABASE dvdrentalold;
ERROR:  wrong tuple length"
```
The similar situation was when I had tried to drop it via command line of Postgres.

So I guessed that the reason of such strange behaviour of my database was in a few hundreds of user roles that I had created earlier and granted to them privilege to connect to the database. It was result of my function which did it basing on the list of customers from the '_customers_' table of the database.
Any attempts to delete (to drop) respective users also failed with similar error messages: "ERROR:  role "client_xxxx_xxxxx" cannot be dropped because some objects depend on it".
So to solve the issue I decided to rewrite my function and do dynamically reassigning of all the owned objects from users to postgres role.
It can be done with the two following commands:
```
REASSIGN OWNED BY client_xxxx_xxxxx TO postgres;
DROP OWNED BY client_xxxx_xxxxx;
```
After it the user client_xxxx_xxxxx can be easily removed:
```
DROP USER client_xxxx_xxxxx;
```

### Dynamical drop of some hundreds of similar roles (users) was done with the following script:
```
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


-- lets execute the function to delete all respective users
SELECT * FROM drop_customer_role();
```
Once all such users were dropped the database was also dropped without any more error message.

P.S. If you wonder why and how I created so many database users, please, consider my study task and function created by me for that purpose.

During my study at EPAM program for Data Engineering I've got the following task:

### 6. Create a personalized role for any customer already existing in the dvd_rental database. 
* The name of the role name must be client_{first_name}_{last_name} (omit curly brackets).
* The customer's payment and rental history must not be empty.

So I prepared a special function to create users with passwords basing on the table '_customer_' for any customer already existing who has got payments and rentals
```
CREATE OR REPLACE FUNCTION create_customer_role()
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
        -- it would be better (more reliable) to concat also email of the user
        role_name := lower('client_' || REPLACE(customer_record.first_name, ' ', '') || '_' || REPLACE(customer_record.last_name, ' ', ''));
        -- we assign user's email as its initial password
        email_password := lower(REPLACE(customer_record.email, ' ', ''));
    
        -- Check if the role_name already exists
        PERFORM 1 FROM pg_roles WHERE rolname = role_name;
        
        IF NOT FOUND THEN
            -- Role doesn't exist, create it
            RAISE NOTICE 'Created for USER ''%'' with password ''%''', role_name, email_password;
            EXECUTE 'CREATE ROLE ' || quote_ident(role_name) || ' LOGIN PASSWORD ' || quote_literal(email_password);
            EXECUTE 'GRANT CONNECT ON DATABASE dvdrental TO ' || quote_ident(role_name);
        ELSE
            RAISE NOTICE 'USER ''%'' already existed. Nothing to do.', role_name;
        END IF
        ;
    END LOOP
    ;
END
;
$$
;


-- lets execute the function to create all respective users
-- it works and doesn't make duplications
SELECT * FROM create_customer_role();
```
