package main

import (
	"os"
	"golang.org/x/crypto/openpgp"
)

func main() {
	keyringFile, err := os.Open(os.Args[1])
	if err != nil { panic(err) }
	keyring, err := openpgp.ReadKeyRing(keyringFile)
	err = openpgp.DetachSign(os.Stdout, keyring[0], os.Stdin, nil)
	if err != nil { panic(err) }
}
