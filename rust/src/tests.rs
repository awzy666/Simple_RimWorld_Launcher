use super::*;
use anyhow::{Context, Result};
use api::{TaskKind, TaskRequest};
use std::{
    fs,
    io::{Cursor, Read, Write},
    net::TcpListener,
    os::windows::fs::OpenOptionsExt,
    path::Path,
};

fn request(kind: TaskKind, path: &Path, source: &str) -> TaskRequest {
    TaskRequest {
        id: "test".into(),
        kind,
        target: path.to_string_lossy().into_owned(),
        source: source.into(),
        folder: String::new(),
        steamcmd: String::new(),
    }
}
fn game(path: &Path) -> Result<String> {
    fs::create_dir_all(path.join("Data/Core"))?;
    fs::write(path.join("RimWorldWin64.exe"), b"fixture")?;
    fs::write(path.join("Version.txt"), "1.6.test")?;
    Ok(path.to_string_lossy().into_owned())
}
fn mod_files(path: &Path, package: &str) -> Result<()> {
    let a = path.join("About");
    fs::create_dir_all(&a)?;
    fs::write(a.join("About.xml"),format!("<ModMetaData><name>Sample</name><packageId>{package}</packageId><author>A</author><supportedVersions><li>1.6</li></supportedVersions></ModMetaData>"))?;
    Ok(())
}
fn archive() -> Result<Vec<u8>> {
    let mut w = zip::ZipWriter::new(Cursor::new(vec![]));
    for (file, bytes) in [
        ("outer/game/RimWorld.exe", "fixture"),
        ("outer/game/Data/Core/marker", "core"),
        ("outer/game/Version.txt", "1.7.test"),
    ] {
        w.start_file(file, zip::write::SimpleFileOptions::default())?;
        w.write_all(bytes.as_bytes())?;
    }
    Ok(w.finish()?.into_inner())
}
fn serve(bytes: Vec<u8>, extra: usize) -> Result<String> {
    let socket = TcpListener::bind("127.0.0.1:0")?;
    let url = format!("http://{}/game.zip", socket.local_addr()?);
    std::thread::spawn(move || {
        let (mut s, _) = socket.accept().unwrap();
        let mut buf = [0u8; 1024];
        let _ = s.read(&mut buf);
        write!(
            s,
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            bytes.len() + extra
        )
        .unwrap();
        s.write_all(&bytes).unwrap();
    });
    Ok(url)
}
#[test]
fn zip_install_existing_and_interrupted_download() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let target = temp.path().join("中文 Game");
    let r = request(TaskKind::InstallGame, &target, &serve(archive()?, 0)?);
    install::component(&r, &|_, _| {})?;
    assert_eq!(discovery::game(&target, false)?.version, "1.7.test");
    assert!(install::component(&r, &|_, _| {}).is_err());
    let dst = temp.path().join("interrupted");
    fs::create_dir(&dst)?;
    let broken = request(TaskKind::InstallGame, &dst, &serve(vec![1, 2, 3], 5000)?);
    assert!(install::component(&broken, &|_, _| {}).is_err());
    assert_eq!(dst.read_dir()?.count(), 0);
    Ok(())
}
#[test]
fn steam_libraries_and_selection() -> Result<()> {
    let t = tempfile::tempdir()?;
    let steam = t.path().join("Steam");
    let second = t.path().join("Other");
    for p in [&steam, &second] {
        let apps = p.join("steamapps");
        game(&apps.join("common/RimWorld"))?;
        fs::write(
            apps.join("appmanifest_294100.acf"),
            r#""AppState" { "appid" "294100" "installdir" "RimWorld" "name" "RimWorld" }"#,
        )?;
    }
    let vdf = format!(
        r#""libraryfolders" {{ "0" {{ "path" "{}" }} "1" {{ "path" "{}" }} }}"#,
        steam.display().to_string().replace('\\', "/"),
        second.display().to_string().replace('\\', "/")
    );
    fs::write(steam.join("steamapps/libraryfolders.vdf"), vdf)?;
    let all = discovery::steam_games(&steamlocate::SteamDir::from_dir(&steam)?);
    assert_eq!(all.len(), 2);
    assert!(all.iter().all(|g| g.steam));
    catalog::scanned(all.clone(), String::new(), true)?;
    catalog::scanned(all.clone(), String::new(), true)?;
    catalog::select(&all[1].path)?;
    let lib = catalog::library()?;
    assert_eq!(lib.selected, all[1].path);
    assert_eq!(lib.games.iter().filter(|g| all.contains(g)).count(), 2);
    Ok(())
}
#[test]
fn mod_lifecycle_recovery_and_locked_files() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let a = game(&temp.path().join("A"))?;
    let b = game(&temp.path().join("B"))?;
    let cache = temp.path().join("123");
    mod_files(&cache, "example.Mod")?;
    fs::write(cache.join("payload"), "new")?;
    let existing = Path::new(&a).join("Mods/HarmonyMod");
    mod_files(&existing, "example.Mod")?;
    fs::write(existing.join("payload"), "original")?;
    let config = Path::new(&a).join("ModsConfig.xml");
    fs::write(&config, "unchanged")?;
    localmods::link(&a, "HarmonyMod", "123")?;
    let handle = fs::OpenOptions::new()
        .read(true)
        .share_mode(0)
        .open(existing.join("payload"))?;
    assert!(localmods::deploy(&a, "HarmonyMod", "123", &cache).is_err());
    drop(handle);
    assert_eq!(fs::read_to_string(existing.join("payload"))?, "original");
    localmods::deploy(&a, "HarmonyMod", "123", &cache)?;
    let installed = localmods::list(&a)?;
    assert_eq!(installed.len(), 1);
    assert_eq!(installed[0].folder, "HarmonyMod");
    assert_eq!(installed[0].versions, "1.6");
    let failed_tool = temp.path().join("steamcmd.exe");
    fs::copy(
        Path::new(&std::env::var("SystemRoot")?).join("System32/where.exe"),
        &failed_tool,
    )?;
    let mut failed = request(TaskKind::InstallMod, Path::new(&a), "123");
    failed.folder = "HarmonyMod".into();
    failed.steamcmd = failed_tool.display().to_string();
    assert!(install::install_mod(&failed, &|_, _| {}).is_err());
    assert_eq!(fs::read_to_string(existing.join("payload"))?, "new");
    fs::write(cache.join("About/About.xml"), "broken")?;
    assert!(localmods::deploy(&a, "HarmonyMod", "123", &cache).is_err());
    assert_eq!(fs::read_to_string(existing.join("payload"))?, "new");
    let work = Path::new(&a).join("Mods/.rimlauncher-transaction");
    fs::create_dir(&work)?;
    storage::write_json(&work.join("target.json"), &"HarmonyMod")?;
    fs::rename(&existing, work.join("old"))?;
    assert_eq!(localmods::list(&a)?[0].item_id, "123");
    assert!(localmods::uninstall(&a, "../Data").is_err());
    localmods::uninstall(&a, "HarmonyMod")?;
    assert!(localmods::list(&a)?.is_empty());
    assert!(localmods::list(&b)?.is_empty());
    assert!(cache.join("payload").exists());
    assert_eq!(fs::read_to_string(config)?, "unchanged");
    Ok(())
}
#[test]
fn scan_cancellation() -> Result<()> {
    let t = tempfile::tempdir()?;
    assert!(discovery::scan(t.path().to_str().unwrap(), &[], "", || true, |_| {}).is_err());
    Ok(())
}

#[test]
fn independent_game_starts_in_selected_directory() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let dir = temp.path().join("中文 游戏");
    let path = game(&dir)?;
    let fixture = temp.path().join("launch_probe.rs");
    fs::write(
        &fixture,
        r#"fn main(){std::fs::write("launched.txt",std::env::current_dir().unwrap().to_str().unwrap()).unwrap();}"#,
    )?;
    let status = std::process::Command::new("rustc")
        .arg(&fixture)
        .arg("-o")
        .arg(dir.join("RimWorldWin64.exe"))
        .status()?;
    assert!(status.success());
    catalog::register(&path)?;
    catalog::launch(&path)?;
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while !dir.join("launched.txt").exists() && std::time::Instant::now() < deadline {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(fs::read_to_string(dir.join("launched.txt"))?, path);
    assert!(catalog::launch(&temp.path().join("missing").display().to_string()).is_err());
    Ok(())
}

#[test]
#[ignore = "requires the local RimWorld and SteamCMD installation"]
fn local_discovery() -> Result<()> {
    let (games, cmd) = discovery::scan("", &[], "", || false, |_| {})?;
    let game = games
        .iter()
        .find(|g| g.version == "1.7.4990 rev1069")
        .context("local installation missing")?;
    let mods = localmods::list(&game.path)?;
    assert!(mods
        .iter()
        .any(|m| m.folder == "HarmonyMod" && m.item_id == "2009463077"));
    assert!(mods
        .iter()
        .any(|m| m.folder == "3223768532" && m.item_id == "3223768532"));
    assert!(discovery::cmd(Path::new(&cmd)).is_some());
    println!("{} | {} | {}", game.path, game.version, cmd);
    Ok(())
}
#[test]
#[ignore = "live Steam services, fresh temporary SteamCMD and test game only"]
fn live_workshop_lifecycle() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let target = temp.path().join("SteamCMD");
    install::component(&request(TaskKind::InstallSteamcmd, &target, ""), &|s, _| {
        println!("{s}")
    })?;
    let page = workshop::search("Smart Speed", 1)?;
    assert!(page.has_next);
    let item = page
        .items
        .iter()
        .find(|m| m.id == "1504723424")
        .context("missing Smart Speed search result")?;
    assert_eq!(workshop::search(&item.id, 1)?.items[0].id, item.id);
    let g = game(&temp.path().join("Game"))?;
    let mut r = request(TaskKind::InstallMod, Path::new(&g), &item.id);
    r.steamcmd = target.join("steamcmd.exe").display().to_string();
    install::install_mod(&r, &|s, _| println!("{s}"))?;
    let list = localmods::list(&g)?;
    assert_eq!(list.len(), 1);
    r.folder = list[0].folder.clone();
    install::install_mod(&r, &|s, _| println!("{s}"))?;
    localmods::uninstall(&g, &r.folder)?;
    assert!(localmods::list(&g)?.is_empty());
    assert!(target
        .join("steamapps/workshop/content/294100/1504723424/About/About.xml")
        .exists());
    Ok(())
}
