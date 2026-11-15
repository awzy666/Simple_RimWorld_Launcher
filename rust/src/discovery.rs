use crate::{api::Game, storage};
use anyhow::{ensure, Result};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};
use walkdir::WalkDir;
use windows_sys::Win32::Storage::FileSystem::{GetDriveTypeW, GetLogicalDrives};

pub fn executable(root: &Path) -> Option<PathBuf> {
    ["RimWorld.exe", "RimWorldWin64.exe"]
        .iter()
        .map(|name| root.join(name))
        .find(|p| p.is_file())
}
pub fn game(root: &Path, steam: bool) -> Result<Game> {
    let root = storage::canonical(root)?;
    ensure!(
        root.join("Data/Core").is_dir() && executable(&root).is_some(),
        "未找到 RimWorld 可执行文件和 Data/Core：{}",
        root.display()
    );
    let version = fs::read_to_string(root.join("Version.txt")).unwrap_or_default();
    Ok(Game {
        path: root.to_string_lossy().into_owned(),
        version: version
            .trim()
            .trim_start_matches('\u{feff}')
            .lines()
            .next()
            .unwrap_or("")
            .to_owned(),
        steam,
    })
}
pub fn cmd(path: &Path) -> Option<PathBuf> {
    let p = if path.is_dir() {
        path.join("steamcmd.exe")
    } else {
        path.into()
    };
    (p.file_name()?
        .to_str()?
        .eq_ignore_ascii_case("steamcmd.exe")
        && p.is_file())
    .then(|| storage::canonical(&p).ok())
    .flatten()
}
fn fixed_disks() -> Vec<PathBuf> {
    let mask = unsafe { GetLogicalDrives() };
    (0..26)
        .filter(|i| mask & (1 << i) != 0)
        .filter_map(|i| {
            let s = format!("{}:\\", (b'A' + i) as char);
            let w = s.encode_utf16().chain(Some(0)).collect::<Vec<_>>();
            (unsafe { GetDriveTypeW(w.as_ptr()) } == 3).then(|| PathBuf::from(s))
        })
        .collect()
}
pub(super) fn steam_games(steam: &steamlocate::SteamDir) -> Vec<Game> {
    steam
        .libraries()
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|lib| {
            let app = lib.app(294100)?.ok()?;
            game(&lib.resolve_app_dir(&app), true).ok()
        })
        .collect()
}
pub fn steam_installations() -> Vec<Game> {
    steamlocate::SteamDir::locate()
        .map(|s| steam_games(&s))
        .unwrap_or_default()
}
pub fn scan(
    root: &str,
    saved: &[Game],
    known_cmd: &str,
    cancelled: impl Fn() -> bool,
    progress: impl Fn(String),
) -> Result<(Vec<Game>, String)> {
    let mut games = BTreeMap::new();
    for g in steam_installations() {
        games.insert(g.path.to_lowercase(), g);
    }
    let mut command = cmd(Path::new(known_cmd));
    let mut roots = Vec::new();
    if root.is_empty() {
        for g in saved {
            if let Ok(v) = game(Path::new(&g.path), false) {
                games.entry(v.path.to_lowercase()).or_insert(v);
            }
        }
        for disk in fixed_disks() {
            for folder in [
                "Games",
                "Game",
                "GameSpace",
                "SteamCMD",
                "SteamLibrary/steamapps/common",
                "Program Files (x86)/Steam/steamapps/common",
                "RimWorld",
            ] {
                roots.push((disk.join(folder), 4));
            }
            if let Ok(entries) = disk.read_dir() {
                for e in entries.flatten() {
                    if e.file_name()
                        .to_string_lossy()
                        .to_lowercase()
                        .contains("rimworld")
                    {
                        roots.push((e.path(), 3));
                    }
                }
            }
        }
        if let Some(path) = std::env::var_os("PATH") {
            for p in std::env::split_paths(&path) {
                command = command.or_else(|| cmd(&p));
            }
        }
    } else {
        ensure!(Path::new(root).is_dir(), "扫描目录不存在");
        roots.push((PathBuf::from(root), usize::MAX));
    }
    for (dir, depth) in roots {
        if cancelled() {
            anyhow::bail!("扫描已取消");
        }
        if !dir.is_dir() {
            continue;
        }
        progress(format!("正在扫描 {}", dir.display()));
        let mut walk = WalkDir::new(&dir)
            .follow_links(false)
            .max_depth(depth)
            .into_iter();
        while let Some(entry) = walk.next() {
            if cancelled() {
                anyhow::bail!("扫描已取消");
            }
            let Ok(e) = entry else { continue };
            if !e.file_type().is_dir() {
                continue;
            }
            if storage::plain(e.path()).is_err() {
                walk.skip_current_dir();
                continue;
            }
            if let Ok(g) = game(e.path(), false) {
                games.entry(g.path.to_lowercase()).or_insert(g);
                walk.skip_current_dir();
                continue;
            }
            if let Some(c) = cmd(e.path()) {
                command = command.or(Some(c));
                walk.skip_current_dir();
                continue;
            }
            if [
                "node_modules",
                ".git",
                "$recycle.bin",
                "system volume information",
                "windows",
                "workshop",
                "depotcache",
                "appdata",
            ]
            .contains(&e.file_name().to_string_lossy().to_lowercase().as_str())
            {
                walk.skip_current_dir();
            }
        }
    }
    Ok((
        games.into_values().collect(),
        command
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default(),
    ))
}
