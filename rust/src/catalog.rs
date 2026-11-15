use crate::{
    api::{Game, Library},
    discovery, storage,
};
use anyhow::{ensure, Context, Result};
use std::{path::Path, process::Command};
fn change<T>(f: impl FnOnce(&mut Library) -> Result<T>) -> Result<T> {
    let _guard = storage::lock("settings")?;
    let file = storage::data_dir()?.join("library.json");
    let mut state: Library = storage::read_json(&file)?;
    let out = f(&mut state)?;
    storage::write_json(&file, &state)?;
    Ok(out)
}
pub fn library() -> Result<Library> {
    let _guard = storage::lock("settings")?;
    let mut state: Library = storage::read_json(&storage::data_dir()?.join("library.json"))?;
    if state.game_url.is_empty() {
        state.game_url = option_env!("RIMWORLD_GAME_ZIP_URL")
            .unwrap_or("")
            .to_owned();
    }
    Ok(state)
}
fn merge(s: &mut Library, g: Game) {
    if let Some(existing) = s
        .games
        .iter_mut()
        .find(|old| old.path.eq_ignore_ascii_case(&g.path))
    {
        *existing = g;
    } else {
        s.games.push(g);
    }
}
pub fn scanned(games: Vec<Game>, cmd: String, deep: bool) -> Result<()> {
    change(|s| {
        s.games
            .retain(|g| discovery::game(Path::new(&g.path), g.steam).is_ok());
        for g in games {
            merge(s, g);
        }
        if !s.games.iter().any(|g| g.path == s.selected) {
            s.selected = s.games.first().map(|g| g.path.clone()).unwrap_or_default();
        }
        if discovery::cmd(Path::new(&s.steamcmd)).is_none() && (!deep || !cmd.is_empty()) {
            s.steamcmd = cmd;
        }
        Ok(())
    })
}
pub fn register(path: &str) -> Result<Game> {
    let mut g = discovery::game(Path::new(path), false)?;
    g.steam = discovery::steam_installations()
        .iter()
        .any(|v| v.path.eq_ignore_ascii_case(&g.path));
    change(|s| {
        merge(s, g.clone());
        s.selected = g.path.clone();
        Ok(g)
    })
}
pub fn select(path: &str) -> Result<()> {
    change(|s| {
        ensure!(s.games.iter().any(|g| g.path == path), "游戏未登记");
        s.selected = path.into();
        Ok(())
    })
}
pub fn set_cmd(path: &str) -> Result<()> {
    let c = discovery::cmd(Path::new(path)).context("目录中找不到 steamcmd.exe")?;
    change(|s| {
        s.steamcmd = c.to_string_lossy().into_owned();
        Ok(())
    })
}
pub fn set_url(url: &str) -> Result<()> {
    if !url.is_empty() {
        storage::url(url)?;
    }
    change(|s| {
        s.game_url = url.to_owned();
        Ok(())
    })
}
pub fn launch(path: &str) -> Result<()> {
    let s = library()?;
    let game = s
        .games
        .iter()
        .find(|g| g.path == path)
        .context("游戏未登记")?;
    let root = Path::new(path);
    discovery::game(root, game.steam)?;
    let mut child = if game.steam {
        let steam = steamlocate::SteamDir::locate().context("无法定位 Steam 客户端")?;
        Command::new(steam.path().join("steam.exe"))
            .args(["-applaunch", "294100"])
            .spawn()
            .context("无法启动 Steam")?
    } else {
        Command::new(discovery::executable(root).context("找不到游戏程序")?)
            .current_dir(root)
            .spawn()
            .context("启动 RimWorld 失败")?
    };
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}
