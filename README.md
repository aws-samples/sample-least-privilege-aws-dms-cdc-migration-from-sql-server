# Least-Privilege AWS DMS CDC Migration from SQL Server

> **Status: INTERNAL STAGING FOR SECURITY REVIEW (PCSR)**
> This repository is staged on gitlab.aws.dev for the Public Content Security Review.
> The final home for this code is an **aws-samples** repository, published through the
> AWS Open Source sample code process. Do not depend on this repository.

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
| `sql/01_create_schema_and_functions.sql` | Creates the `awsdms` schema and heartbeat helper function |
| `sql/02_create_stored_procedures.sql` | Wrapper procedures for `fn_dump_dblog` and `fn_position_1st_timestamp` |
| `sql/03_create_certificates_and_sign.sql` | Certificates, certificate-based logins, and `ADD SIGNATURE` |
| `sql/04_grant_permissions.sql` | Granular grants for the non-sysadmin DMS user |
| `sql/05_ag_replica_setup.sql` | Always On AG replica setup (SID-consistent login, per-replica certificates) |
| `cloudformation/dms-nonsysadmin-secrets.yaml` | Secrets Manager secrets and scoped IAM role for the DMS endpoint |
| `cleanup/remove_nonsysadmin_setup.sql` | Removes all objects in dependency order |

## Usage

1. Run the SQL scripts in order (01 → 04) against the `master` database on your source
   SQL Server instance. Pass certificate passwords as SQLCMD variables — never hardcode them.
2. Deploy the CloudFormation template to create the secrets and IAM role.
3. Create the DMS source endpoint referencing the secret, with the
   `enableNonSysadminWrapper=true;` extra connection attribute.
4. For Always On AG environments, additionally run `05_ag_replica_setup.sql` on every replica.

See the blog post for the full walkthrough, validation steps, and limitations. For the
authoritative procedure definitions, see
[Using a non-sysadmin user with AWS DMS](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.SQLServer.html#CHAP_Source.SQLServer.Configuration.nonsysadmin).

## Security

These scripts grant sysadmin to certificate-based logins only. The certificate logins
have no password and cannot establish a session. Store all passwords in AWS Secrets Manager.

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for reporting security issues.

## License

This library is licensed under the MIT-0 License. See the [LICENSE](LICENSE) file.
