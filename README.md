# Run Least-Privilege AWS DMS CDC Migration from SQL Server

This sample supports the AWS Database Blog walkthrough for running AWS Database Migration Service (AWS DMS) change data capture (CDC) from a self-managed SQL Server source without granting `sysadmin` to the DMS endpoint login.

The tested implementation uses SQL Server certificate-signed wrapper procedures. The DMS login receives the verified minimum working permissions, while two non-interactive certificate logins activate `sysadmin` only while the signed modules execute.

## Repository contents

| Path | Purpose |
|---|---|
| `sql/00_configure_replication.sql` | Configures distribution, a DMS-compatible publication, and filtered articles for primary-key tables |
| `dms_setup_standalone_nonsysadmin.sql` | All-in-one, version-aware standalone SQL Server setup |
| `sql/01_create_schema_and_functions.sql` | Creates `awsdms.split_partition_list` |
| `sql/02_create_stored_procedures.sql` | Creates the same version-aware wrappers as the all-in-one setup |
| `sql/03_create_certificates_and_sign.sql` | Creates the canonical certificates/logins and signs the wrappers |
| `sql/04_grant_permissions.sql` | Applies the verified master, msdb, source database, and server grants |
| `sql/05_ag_replica_setup.sql` | Validates/creates the matched-SID AG login, then reuses scripts 01-04 |
| `cloudformation/dms-nonsysadmin-secrets.yaml` | Creates KMS-encrypted secrets and the regional DMS service role |
| `cleanup/remove_nonsysadmin_setup.sql` | Removes canonical wrapper objects, certificate logins, and grants |

## Prerequisites

- A self-managed SQL Server source version supported by AWS DMS, using full or bulk-logged recovery
- A SQL Server login dedicated to the DMS endpoint; the standalone setup validates that it already exists
- An edition that can act as a transactional replication publisher, such as Standard or Enterprise. Express and Web editions can only be subscribers, so the publication step fails on them.
- SQL Server authentication (Mixed Mode) enabled, because the DMS endpoint uses a password-based SQL login. `SELECT SERVERPROPERTY('IsIntegratedSecurityOnly')` must return `0`; changing it requires a service restart.
- A replication working directory that already exists and is writable by the SQL Server Agent service account. Distribution setup fails otherwise.
- `sysadmin` access for the one-time distribution, publication, certificate, and signing setup
- SQLCMD for the modular and cleanup commands
- An AWS DMS replication instance that can reach the SQL Server source and AWS Secrets Manager
- For a private DMS instance without internet egress, a Secrets Manager interface VPC endpoint with private DNS and TCP 443 access from the DMS security group

DMS endpoint passwords cannot contain semicolon (`;`), plus (`+`), or percent (`%`) characters.

Validated on SQL Server 2022 Standard Edition (16.0.4265.3) with AWS DMS 3.5.4.

## Quick start

### 1. Configure SQL Server replication

Run from the repository root and source database context:

```bash
sqlcmd -S <server> -d <source-database> \
  -i sql/00_configure_replication.sql \
  -v REPLDATA_DIR="C:\Program Files\Microsoft SQL Server\MSSQL\ReplData" \
     CREATE_PUBLICATION="1"
```

`REPLDATA_DIR` must already exist and be writable by the SQL Server Agent service account.

The script configures the instance as its own distributor when needed, creates a continuous anonymous publication, and adds primary-key user tables as log-based articles with the deliberate `(1=0)` filter. Run this command on a standalone source or the AG primary. Script 05 runs the same file with `CREATE_PUBLICATION=0` to configure distribution on each AG secondary without creating duplicate publication state. Tables without primary keys are not added; configure MS-CDC separately if you need to capture them.

### 2. Deploy Secrets Manager resources

```bash
aws cloudformation deploy \
  --template-file cloudformation/dms-nonsysadmin-secrets.yaml \
  --stack-name dms-nonsysadmin-secrets \
  --parameter-overrides \
      DMSUsername=dmsnosysadmin \
      DMSPassword=<endpoint-password-without-semicolon-plus-percent> \
      SQLServerHost=<sql-server-host-or-ag-listener> \
      CertPassword=<certificate-password> \
  --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
```

`CAPABILITY_AUTO_EXPAND` is required because the template uses the
`AWS::LanguageExtensions` transform to build the secret JSON. The transform keeps
each password as a parameter reference, so `NoEcho` protection is preserved and no
plaintext password appears in the processed template.

The DMS role trusts both `dms.amazonaws.com` and the Region-specific principal `dms.<region>.amazonaws.com`. It can read only the endpoint credential secret. The certificate password secret remains operator-only.

For an on-premises source whose policy prohibits cloud-stored credentials, skip this template and provide the credentials directly when you create the DMS endpoint.

### 3. Configure the non-sysadmin wrappers

Choose one setup path.

**Option A - all-in-one standalone setup:** edit the three `CHANGE ME` values in `dms_setup_standalone_nonsysadmin.sql`, then run it as `sysadmin`.

```bash
sqlcmd -S <server> -i dms_setup_standalone_nonsysadmin.sql
```

**Option B - modular standalone setup:** run scripts 01-04 in order from the repository root. Both paths create the same helper, procedure contracts, canonical object names, signatures, and verified grants.

```bash
sqlcmd -S <server> -i sql/01_create_schema_and_functions.sql
sqlcmd -S <server> -i sql/02_create_stored_procedures.sql
sqlcmd -S <server> -i sql/03_create_certificates_and_sign.sql \
  -v CERT_PASSWORD="<certificate-password>"
sqlcmd -S <server> -i sql/04_grant_permissions.sql \
  -v DMS_USER="dmsnosysadmin" DB_NAME="<source-database>"
```

### 4. Configure each Always On AG replica

Get the login SID from the primary:

```sql
SELECT CONVERT(VARCHAR(200), sid, 1) AS primary_sid
FROM sys.server_principals
WHERE name = N'dmsnosysadmin';
```

Then run the AG script from the repository root on each replica:

```bash
sqlcmd -S <replica-server> -i sql/05_ag_replica_setup.sql \
  -v DMS_USER="dmsnosysadmin" \
     DMS_PASSWORD="<endpoint-password>" \
     PRIMARY_SID="0x..." \
     CERT_PASSWORD="<certificate-password>" \
     DB_NAME="<source-database>" \
     REPLDATA_DIR="C:\Program Files\Microsoft SQL Server\MSSQL\ReplData"
```

The AG script configures distribution locally on the replica, validates or creates the matched-SID login, and reuses canonical scripts 01-04. Run the Step 1 publication command once on the primary with `CREATE_PUBLICATION=1`; script 05 uses distribution-only mode on secondaries.

### 5. Create the DMS source endpoint

```bash
aws dms create-endpoint \
  --endpoint-identifier sqlserver-source \
  --endpoint-type source \
  --engine-name sqlserver \
  --database-name master \
  --microsoft-sql-server-settings \
      "SecretsManagerSecretId=<endpoint-secret-arn>,SecretsManagerAccessRoleArn=<dms-role-arn>" \
  --extra-connection-attributes "enableNonSysadminWrapper=true;"
```

The Secrets Manager fields belong inside `--microsoft-sql-server-settings`; AWS DMS
has no top-level `--secrets-manager-secret-id` option. `--database-name` is still
required even when the secret contains `dbname`.

## Validation

Verify that the DMS login has no `sysadmin` membership:

```sql
SELECT IS_SRVROLEMEMBER(N'sysadmin', N'dmsnosysadmin') AS is_sysadmin;
```

Expected output: `0`.

Confirm that elevation is scoped to the signed procedures. In an impersonated session
(`EXECUTE AS LOGIN = N'dmsnosysadmin'`), a direct `sys.fn_dump_dblog` call is refused with
error 9010, while `master.awsdms.rtm_dump_dblog` returns log records in that same session.
`CREATE LOGIN` remains denied with error 15247.

After starting CDC, the `SOURCE_CAPTURE` task log should contain these object checks:

```text
Object ('awsdms','split_partition_list','TF') exists at MASTER
Object ('awsdms','rtm_dump_dblog','P') exists at MASTER
```

## Cleanup

The cleanup removes both canonical certificate-based sysadmin logins, their certificates and signatures, the wrapper procedures, `split_partition_list`, and the exact grants applied by this sample. It never drops the pre-existing DMS server login or shared distribution configuration.

On a standalone source or AG primary, remove the sample publication and source-database grants:

```bash
sqlcmd -S <server> -i cleanup/remove_nonsysadmin_setup.sql \
  -v DMS_USER="dmsnosysadmin" DB_NAME="<source-database>" \
     REMOVE_DMS_USERS="1" CLEAN_SOURCE_DATABASE="1" REMOVE_PUBLICATION="1"
```

On every AG secondary, remove local wrappers, certificate logins, and `master`/`msdb` grants without modifying the read-only source database:

```bash
sqlcmd -S <replica-server> -i cleanup/remove_nonsysadmin_setup.sql \
  -v DMS_USER="dmsnosysadmin" DB_NAME="<source-database>" \
     REMOVE_DMS_USERS="1" CLEAN_SOURCE_DATABASE="0" REMOVE_PUBLICATION="0"
```

Use `REMOVE_DMS_USERS="0"` if the database users predated this walkthrough or support another workload.

## Security

- The DMS endpoint login has no elevated server role membership.
- Certificate-based logins are non-interactive and activate their permissions only inside signed procedures.
- The DMS IAM role reads only the endpoint credential secret and decrypts only through regional Secrets Manager.
- All secrets use a customer managed KMS key with rotation enabled.

## License

This sample is licensed under the MIT-0 License. See [LICENSE](LICENSE).
