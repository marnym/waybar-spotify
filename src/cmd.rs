use std::{
    io::{BufRead, BufReader},
    process::{Command, Stdio},
    sync::mpsc::Sender,
};

pub enum Output {
    Status(String),
    Metadata(String),
}

pub fn playerctl_spotify_cmd(args: &[&str]) -> Command {
    let mut cmd = Command::new("playerctl");
    cmd.args(["--player", "spotify", "--follow"]);
    cmd.args(args);
    cmd
}

pub fn listen_to_cmd(tx: Sender<Output>, cmd: &mut Command, cmd_output: fn(String) -> Output) {
    let process = match cmd.stdout(Stdio::piped()).spawn() {
        Err(reason) => panic!("couldnt spawn playerctl: {}", reason),
        Ok(process) => process,
    };

    let mut reader = BufReader::new(process.stdout.unwrap());
    let mut line = String::new();
    while reader.read_line(&mut line).unwrap() > 0 {
        tx.send(cmd_output(line.trim().to_string())).unwrap();
        line.clear();
    }
    drop(tx);
}
