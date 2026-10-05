package deskts

import "testing"

func TestParseInterfaces(t *testing.T) {
	l := parseInterfaces("wlan0 3 1500 1 1 0 0 1 10.0.2.16/24 fe80::1%wlan0/64\nlo 1 65536 1 0 1 0 0 127.0.0.1/8\nbad")
	if len(l) != 2 || l[0].Name != "wlan0" || !l[0].IsUp() || l[1].IsLoopback() == false {
		t.Fatalf("%+v", l)
	}
	if a, _ := l[0].Addrs(); len(a) != 1 || a[0].String() != "10.0.2.16/24" {
		t.Fatalf("addrs %v", a)
	}
}
