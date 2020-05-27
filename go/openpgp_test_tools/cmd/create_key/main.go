package main

import (
	"os"
	"golang.org/x/crypto/openpgp"
	"golang.org/x/crypto/openpgp/armor"
)

func main() {
	entity, err := openpgp.NewEntity("Test Key", "Do Not Trust", "test@example.com", nil)
	if err != nil { panic(err) }
	armoringEncoder, err := armor.Encode(os.Stdout, openpgp.PrivateKeyType, nil)
	if err != nil { panic(err) }
	err = entity.SerializePrivate(armoringEncoder, nil)
	if err != nil { panic(err) }
	err = armoringEncoder.Close()
	if err != nil { panic(err) }
}
