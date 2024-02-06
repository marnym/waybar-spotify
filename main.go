package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"strings"
)

type State struct {
	Playing  bool   `json:"playing"`
	Metadata string `json:"text"`
}

func listenToCmd(events chan string, cmd *exec.Cmd, b []byte) {
	cmdOut, err := cmd.StdoutPipe()
	cmd.Start()

	var n int
	for err == nil {
		n, err = cmdOut.Read(b)
		events <- strings.TrimRight(string(b[:n]), "\n")
	}
	cmd.Wait()
}

func main() {
	done := make(chan bool, 1)
	statuses := make(chan string)
	metadatas := make(chan string)

	go func() {
		state := State{
			Playing:  false,
			Metadata: "",
		}
		e := json.NewEncoder(os.Stdout)
		e.SetEscapeHTML(false)
		for {
			select {
			case status := <-statuses:
				state.Playing = status == "Playing"
			case metadata := <-metadatas:
				state.Metadata = metadata
			}
			e.Encode(state)
		}
	}()

	go listenToCmd(statuses, exec.Command("playerctl", "--player", "spotify", "--follow", "status"), make([]byte, 8))
	go listenToCmd(
		metadatas,
		exec.Command("playerctl", "--player", "spotify", "--follow", "--format", "{{ artist }} - {{ title }}", "metadata"),
		make([]byte, 64),
	)

	<-done
}
