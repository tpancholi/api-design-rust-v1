-- Enable required migrations
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
-- Create users table
CREATE TABLE users
(
    id                uuid NOT NULL,
    PRIMARY KEY (id),
    email             CITEXT NOT NULL UNIQUE,
    password_hash     TEXT NOT NULL,
    is_email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Lowercase email constraint for consistency
CREATE UNIQUE INDEX users_email_lower_idx ON users (lower(email));
