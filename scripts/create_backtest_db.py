#!/usr/bin/env python3
"""Create the isolated `nexusquant_backtest` database and its login role.

Run ONCE (idempotent: safe to re-run) after `terraform apply` has created the
secret `/<project>/<env>/backtest/db`. RDS is private, so open an SSM
port-forward first (see README of this script's usage below) and point --host /
--port at it.

  # terminal 1 (leave open)
  aws ssm start-session --region eu-north-1 --target <ec2_windows_instance_id> `
    --document-name AWS-StartPortForwardingSessionToRemoteHost `
    --parameters "host=<rds_endpoint>,portNumber=5432,localPortNumber=15432"

  # terminal 2
  python scripts/create_backtest_db.py

Credentials are never typed: the RDS master user is read from the adapter
secret and the backtest user/password from the backtest secret, both in
AWS Secrets Manager (needs your normal AWS CLI credentials).

Requires: pip install boto3 "psycopg[binary]"   (psycopg2 also works)
"""
from __future__ import annotations

import argparse
import json
import sys

import boto3

try:  # the app uses psycopg 3 ("postgresql+psycopg://"), fall back to psycopg2
    import psycopg as pg
    from psycopg import sql
except ImportError:  # pragma: no cover
    try:
        import psycopg2 as pg
        from psycopg2 import sql
    except ImportError:
        sys.exit('Missing driver: pip install "psycopg[binary]"')


def get_secret(client, secret_id: str) -> dict:
    return json.loads(client.get_secret_value(SecretId=secret_id)["SecretString"])


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--project", default="nexusquant")
    p.add_argument("--env", default="dev")
    p.add_argument("--region", default="eu-north-1")
    p.add_argument("--host", default="127.0.0.1", help="RDS host as seen from here (SSM tunnel: 127.0.0.1)")
    p.add_argument("--port", type=int, default=15432, help="local tunnel port")
    p.add_argument("--connection-limit", type=int, default=40,
                   help="max concurrent connections of the backtest role (protects the live engine)")
    args = p.parse_args()

    sm = boto3.client("secretsmanager", region_name=args.region)
    master = get_secret(sm, f"/{args.project}/{args.env}/mt5-adapter/secrets")
    bt = get_secret(sm, f"/{args.project}/{args.env}/backtest/db")
    role, password, dbname = bt["DB_USERNAME"], bt["DB_PASSWORD"], bt["DB_NAME"]
    master_user = master["DB_USERNAME"]

    conn = pg.connect(
        host=args.host, port=args.port, dbname="postgres",
        user=master_user, password=master["DB_PASSWORD"],
        sslmode="require", connect_timeout=15,
    )
    conn.autocommit = True  # CREATE DATABASE cannot run inside a transaction
    cur = conn.cursor()

    # 1) login role (create, or re-sync password/limit with the secret)
    cur.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (role,))
    verb = "ALTER" if cur.fetchone() else "CREATE"
    cur.execute(sql.SQL("{} ROLE {} LOGIN PASSWORD {} CONNECTION LIMIT {}").format(
        sql.SQL(verb), sql.Identifier(role), sql.Literal(password), sql.Literal(args.connection_limit)))
    print(f"role {role}: {verb.lower()}d (connection limit {args.connection_limit})")

    # 2) RDS master is not a real superuser: it must be able to SET ROLE to the
    #    future owner, otherwise CREATE DATABASE ... OWNER fails.
    cur.execute(sql.SQL("GRANT {} TO {}").format(sql.Identifier(role), sql.Identifier(master_user)))

    # 3) database owned by the backtest role
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (dbname,))
    if cur.fetchone():
        print(f"database {dbname}: already exists")
    else:
        cur.execute(sql.SQL("CREATE DATABASE {} OWNER {} ENCODING 'UTF8'").format(
            sql.Identifier(dbname), sql.Identifier(role)))
        print(f"database {dbname}: created")

    # 4) isolation: only the owner (and the master) can connect
    cur.execute(sql.SQL("REVOKE ALL ON DATABASE {} FROM PUBLIC").format(sql.Identifier(dbname)))
    conn.close()

    # 5) smoke test as the backtest user, on its own database
    t = pg.connect(host=args.host, port=args.port, dbname=dbname, user=role, password=password,
                   sslmode="require", connect_timeout=15)
    tc = t.cursor()
    tc.execute("SELECT current_user, current_database()")
    print("login test OK:", tc.fetchone())
    t.close()


if __name__ == "__main__":
    main()
