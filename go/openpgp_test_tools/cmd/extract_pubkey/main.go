package main

import (
	"os"
	"golang.org/x/crypto/openpgp"
	"golang.org/x/crypto/openpgp/armor"
)

func main() {
	armoringEncoder, err := armor.Encode(os.Stdout, openpgp.PublicKeyType, nil)
	if err != nil { panic(err) }

	keyring, err := openpgp.ReadArmoredKeyRing(os.Stdin)
	if err != nil { panic(err) }
	for _, entity := range keyring {
		err = entity.Serialize(armoringEncoder)
		if err != nil { panic(err) }
	}
	err = armoringEncoder.Close()
	if err != nil { panic(err) }
}

