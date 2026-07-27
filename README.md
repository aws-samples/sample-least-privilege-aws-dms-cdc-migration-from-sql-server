# Run Least-Privilege AWS DMS CDC Migration from SQL Server

> **Disclaimer:** This is sample code, for non-production usage. You should work with
> your security and legal teams to meet your organizational security, regulatory and
> compliance requirements before deployment.

Sample code accompanying the AWS Database Blog post *Run Least-Privilege AWS DMS CDC
Migration from SQL Server*. It configures AWS Database Migration Service (AWS DMS)
change data capture (CDC) from a SQL Server source **without granting sysadmin** to the
DMS user account, using SQL Server certificate-based code signing and AWS Secrets Manager.

## Contents

| Path | Purpose |
|------|---------|
| `dms_setup_standalone_nonsysadmin.sql` | All-in-one setup script for standalone SQL Server (version-aware; auto-detects `fn_dump_dblog` parameters for SQL Server 2016–2022) |
| `sql/01_create_schema_and_functions.sql` | Creates the `awsdms` schema and heartbeat helper function |
| `sql/02_create_stored_procedures.sql` | Wrapper procedures for `fn_dump_dblog` and `fn_position_1st_timestamp` |
| `sql/03_create_certificates_and_sign.sql` | Certificates, certificate-based logins, and `ADD SIGNATURE` |
| `sql/04_grant_permissions.sql` | Granular grants for the non-sysadmin DMS user |
| `sql/05_ag_replica_setup.sql` | Always On AG replica setup (SID-consistent login, per-replica certificates) |
| `cloudformation/dms-nonsysadmin-secrets.yaml` | Secrets Manager secrets and scoped IAM role for the DMS endpoint |
| `cleanup/remove_nonsysadmin_setup.sql` | Removes all objects in dependency order |

## Usage

**Option A — All-in-one script (standalone SQL Server):**

1. Open `dms_setup_standalone_nonsysadmin.sql` and set the three `CHANGE ME` values
   (DMS login, source database, certificate password). Never commit or reuse the
   placeholder password.
2. Run the script as sysadmin. It auto-detects your SQL Server version and creates all
   objects, certificates, signatures, and grants in one pass.

**Option B — Step-by-step scripts:**

1. Run the SQL scripts in order (01 → 04) against the `master` database on your source
   SQL Server instance. Pass certificate passwords as SQLCMD variables — never hardcode them.
2. For Always On AG environments, additionally run `05_ag_replica_setup.sql` on every replica.

**Then, for both options:**

3. If your source endpoint uses AWS Secrets Manager for credentials (recommended for
   sources reachable from AWS), deploy the CloudFormation template to create the secrets
   and IAM role. For on-premises sources where you supply credentials directly on the
   DMS endpoint, the CloudFormation template is optional.
4. Create the DMS source endpoint with the `enableNonSysadminWrapper=true;` extra
   connection attribute.

See the blog post for the full walkthrough, validation steps, and limitations. For the
authoritative procedure definitions, see
[Using a non-sysadmin user with AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.Configuration.nonsysadmin).

## Security

These scripts grant sysadmin to certificate-based logins only. The certificate logins
have no password and cannot establish a session. Store all passwords in AWS Secrets Manager.

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for reporting security issues.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
