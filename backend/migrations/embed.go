// Package migrations embeds the SQL schema files so the binary can migrate a
// database on its own, with no external tool to install.
package migrations

import "embed"

// FS holds every .sql file in this directory, applied in filename order.
//
//go:embed *.sql
var FS embed.FS
