package main

import (
	"os"
	"golang.org/x/crypto/openpgp"
)

func main() {
	entity, err := openpgp.NewEntity("Test Key", "Do Not Trust", "test@example.com", nil)
	if err != nil { panic(err) }
	err = entity.SerializePrivate(os.Stdout, nil)
	if err != nil { panic(err) }
}
