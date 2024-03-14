use waybar_spotify::cmd;

use std::{
    sync::mpsc::{self},
    thread,
};

use serde::Serialize;

#[derive(Serialize)]
struct State {
    #[serde(rename(serialize = "class"))]
    playing: String,
    #[serde(rename(serialize = "text"))]
    metadata: String,
}

fn main() {
    let (tx, rx) = mpsc::channel::<cmd::Output>();

    let status_tx = tx.clone();
    thread::spawn(move || {
        cmd::listen_to_cmd(
            status_tx.clone(),
            &mut cmd::playerctl_spotify_cmd(&["status"]),
            cmd::Output::Status,
        );
    });

    let metadata_tx = tx.clone();
    thread::spawn(move || {
        cmd::listen_to_cmd(
            metadata_tx,
            &mut cmd::playerctl_spotify_cmd(&[
                "--format",
                "{{ artist }} - {{ title }}",
                "metadata",
            ]),
            cmd::Output::Metadata,
        );
    });

    let mut state = State {
        playing: "".to_string(),
        metadata: "".to_string(),
    };

    loop {
        match rx.recv().unwrap() {
            cmd::Output::Status(s) => {
                state.playing = if s == "Playing" {
                    "playing".to_owned()
                } else {
                    "".to_owned()
                };
            }
            cmd::Output::Metadata(s) => {
                state.metadata = s;
            }
        };

        println!("{}", serde_json::to_string(&state).unwrap());
    }
}
