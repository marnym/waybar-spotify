package main

import (
	"bufio"
	"encoding/json"
	"os"
	"os/exec"
)

type State struct {
	Playing  string `json:"class"`
	Metadata string `json:"text"`
}

func listenToCmd(events chan string, cmd *exec.Cmd) {
	cmdOut, err := cmd.StdoutPipe()
	if err != nil {
		panic(err)
	}
	cmd.Start()

	scanner := bufio.NewScanner(cmdOut)
	for scanner.Scan() {
		line := scanner.Text()
		events <- line
	}
	cmd.Wait()
}

func main() {
	done := make(chan bool, 1)
	statuses := make(chan string)
	metadatas := make(chan string)

	go func() {
		state := State{
			Playing:  "",
			Metadata: "",
		}
		e := json.NewEncoder(os.Stdout)
		e.SetEscapeHTML(false)
		for {
			select {
			case status := <-statuses:
				if status == "Playing" {
					state.Playing = "playing"
				} else {
					state.Playing = ""
				}
			case metadata := <-metadatas:
				state.Metadata = metadata
			}
			e.Encode(state)
		}
	}()

	go listenToCmd(statuses, exec.Command("playerctl", "--player", "spotify", "--follow", "status"))
	go listenToCmd(metadatas, exec.Command("playerctl", "--player", "spotify", "--follow", "--format", "{{ artist }} - {{ title }}", "metadata"))

	<-done
}
