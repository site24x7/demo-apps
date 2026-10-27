package chaos

import (
	"bufio"
	"context"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// Stop must return promptly while connected to an agent that sends nothing:
// the client used to block in Read until the agent's next message.
func TestUDSStopWhileConnected(t *testing.T) {
	dir, err := os.MkdirTemp("", "uds")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(dir)
	sock := filepath.Join(dir, "a.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	connected := make(chan struct{})
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		bufio.NewReader(c).ReadString('\n') // the register message
		close(connected)
		// then stay silent
	}()

	c := NewUDSClient(sock, "i1", "app", "go", "test", "host", 1, nil, 60000, 100, nil, nil, nil)
	c.Start(context.Background())
	select {
	case <-connected:
	case <-time.After(5 * time.Second):
		t.Fatal("client never connected")
	}

	stopped := make(chan struct{})
	go func() { c.Stop(); close(stopped) }()
	select {
	case <-stopped:
	case <-time.After(2 * time.Second):
		t.Fatal("Stop hung while the agent was silent")
	}
}
