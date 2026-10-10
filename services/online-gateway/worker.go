package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"sync"
	"time"
)

type Worker struct {
	conn net.Conn
	cmd  *exec.Cmd
	mu   sync.Mutex
}

func startWorker(godot, project, matchID string) (*Worker, error) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	defer listener.Close()
	cmd := exec.Command(godot, "--headless", "--path", project, "--script", "res://server/server_main.gd", "--", "--epoch-match="+matchID)
	cmd.Env = append(os.Environ(), fmt.Sprintf("EPOCH_WORKER_PORT=%d", listener.Addr().(*net.TCPAddr).Port))
	cmd.Stdout = io.Discard
	cmd.Stderr = os.Stderr
	if err = cmd.Start(); err != nil {
		return nil, err
	}
	_ = listener.(*net.TCPListener).SetDeadline(time.Now().Add(15 * time.Second))
	conn, err := listener.Accept()
	if err != nil {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		return nil, err
	}
	return &Worker{conn: conn, cmd: cmd}, nil
}

func (w *Worker) request(request Object) (*WorkerResponse, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	_ = w.conn.SetDeadline(time.Now().Add(time.Second))
	payload := encode(request)
	if len(payload) > 4194304 {
		return nil, fmt.Errorf("worker request too large")
	}
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(payload)))
	if _, err := io.Copy(w.conn, bytesReader(append(header, payload...))); err != nil {
		return nil, err
	}
	if _, err := io.ReadFull(w.conn, header); err != nil {
		return nil, err
	}
	size := binary.BigEndian.Uint32(header)
	if size < 2 || size > 4194304 {
		return nil, fmt.Errorf("worker response exceeds limit")
	}
	response := make([]byte, size)
	if _, err := io.ReadFull(w.conn, response); err != nil {
		return nil, err
	}
	var result WorkerResponse
	if err := json.Unmarshal(response, &result); err != nil {
		return nil, err
	}
	if result.Error != "" {
		return nil, fmt.Errorf("worker: %s", result.Error)
	}
	return &result, nil
}
func (w *Worker) close() { _ = w.conn.Close(); _ = w.cmd.Process.Kill(); _ = w.cmd.Wait() }
