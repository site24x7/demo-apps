package fault

import "testing"

func TestValidIdentifiers(t *testing.T) {
	for _, ok := range []string{"orders", "order_items", "public.orders", "_t1"} {
		if !validIdentifiers("test", ok) {
			t.Errorf("%q rejected", ok)
		}
	}
	for _, bad := range []string{"", "orders; DROP TABLE users", "orders--", "a b", "1orders", "a.b.c", `"orders"`, "orders)"} {
		if validIdentifiers("test", bad) {
			t.Errorf("%q accepted", bad)
		}
	}
}
