package main

import (
	"os"
	"golang.org/x/crypto/openpgp"
)

func main() {
	keyring, err := openpgp.ReadKeyRing(os.Stdin)
	if err != nil { panic(err) }
	for _, entity := range keyring {
		err = entity.Serialize(os.Stdout)
		if err != nil { panic(err) }
	}
}
