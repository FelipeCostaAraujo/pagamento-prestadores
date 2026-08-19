package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"golang.org/x/term"

	"github.com/felipearaujo/diarias/backend/internal/config"
	"github.com/felipearaujo/diarias/backend/internal/db"
	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

const userUsage = `Gerenciamento de usuários.

  api user add <usuário>       cria uma conta
  api user list                lista as contas
  api user passwd <usuário>    troca a senha (encerra as sessões abertas)
  api user disable <usuário>   bloqueia o acesso
  api user enable <usuário>    libera o acesso de novo

A senha é lida da entrada padrão. Num terminal ela é pedida sem eco; via pipe
basta mandar o texto:

  docker compose exec -T api /api user add felipe <<< 'senha-bem-longa'
`

// runUserCommand handles `api user ...`. It shares the API's configuration and
// migrations, so `docker compose exec api /api user add <nome>` works against
// the running database with no extra tooling on the VM.
func runUserCommand(args []string) error {
	if len(args) == 0 || args[0] == "help" || args[0] == "-h" || args[0] == "--help" {
		fmt.Print(userUsage)
		return nil
	}

	cfg, err := config.Load(".env", "../.env")
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		return err
	}
	st := store.New(pool)

	action := args[0]
	rest := args[1:]

	needsName := action == "add" || action == "passwd" ||
		action == "disable" || action == "enable"
	if needsName && len(rest) != 1 {
		return fmt.Errorf("uso: api user %s <usuário>", action)
	}

	switch action {
	case "add":
		return addUser(ctx, st, rest[0])
	case "list":
		return listUsers(ctx, st)
	case "passwd":
		return changeUserPassword(ctx, st, rest[0])
	case "disable":
		return setUserDisabled(ctx, st, rest[0], true)
	case "enable":
		return setUserDisabled(ctx, st, rest[0], false)
	default:
		return fmt.Errorf("comando desconhecido %q\n\n%s", action, userUsage)
	}
}

func addUser(ctx context.Context, st *store.Store, username string) error {
	if err := store.ValidateUsername(username); err != nil {
		return err
	}

	password, err := readPassword("Senha para " + username + ": ")
	if err != nil {
		return err
	}

	user, err := st.CreateUser(ctx, username, password)
	if errors.Is(err, store.ErrUsernameTaken) {
		return fmt.Errorf("o usuário %q já existe", username)
	}
	if err != nil {
		return err
	}

	fmt.Printf("usuário %s criado\n", user.Username)
	return nil
}

func listUsers(ctx context.Context, st *store.Store) error {
	users, err := st.ListUsers(ctx)
	if err != nil {
		return err
	}
	if len(users) == 0 {
		fmt.Println("nenhum usuário cadastrado — a API vai recusar todo acesso")
		return nil
	}

	fmt.Printf("%-24s %-10s %s\n", "USUÁRIO", "ESTADO", "CRIADO EM")
	for _, u := range users {
		state := "ativo"
		if u.DisabledAt != nil {
			state = "bloqueado"
		}
		fmt.Printf("%-24s %-10s %s\n",
			u.Username, state, u.CreatedAt.Local().Format("2006-01-02 15:04"))
	}
	return nil
}

func changeUserPassword(ctx context.Context, st *store.Store, username string) error {
	password, err := readPassword("Nova senha para " + username + ": ")
	if err != nil {
		return err
	}
	if err := st.SetPassword(ctx, username, password); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return fmt.Errorf("usuário %q não encontrado", username)
		}
		return err
	}
	fmt.Printf("senha de %s alterada; as sessões abertas foram encerradas\n", username)
	return nil
}

func setUserDisabled(ctx context.Context, st *store.Store, username string, disabled bool) error {
	if err := st.SetUserDisabled(ctx, username, disabled); err != nil {
		if errors.Is(err, domain.ErrNotFound) {
			return fmt.Errorf("usuário %q não encontrado", username)
		}
		return err
	}
	if disabled {
		fmt.Printf("%s bloqueado; as sessões abertas foram encerradas\n", username)
	} else {
		fmt.Printf("%s liberado\n", username)
	}
	return nil
}

// readPassword takes the password from stdin without ever putting it in a
// command-line argument, where it would land in shell history and in `ps`.
//
// On a terminal it is read with echo off and confirmed; when piped it is read
// as a single line, which is what makes the command usable from a script.
func readPassword(prompt string) (string, error) {
	fd := int(os.Stdin.Fd())

	if !term.IsTerminal(fd) {
		line, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil && line == "" {
			return "", fmt.Errorf("ler senha da entrada padrão: %w", err)
		}
		return strings.TrimRight(line, "\r\n"), nil
	}

	fmt.Print(prompt)
	first, err := term.ReadPassword(fd)
	fmt.Println()
	if err != nil {
		return "", fmt.Errorf("ler senha: %w", err)
	}

	fmt.Print("Repita a senha: ")
	second, err := term.ReadPassword(fd)
	fmt.Println()
	if err != nil {
		return "", fmt.Errorf("ler senha: %w", err)
	}

	if string(first) != string(second) {
		return "", errors.New("as senhas não conferem")
	}
	return string(first), nil
}
