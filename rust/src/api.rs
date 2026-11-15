use crate::frb_generated::StreamSink;
use anyhow::Result;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Game {
    pub path: String,
    pub version: String,
    pub steam: bool,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Library {
    pub games: Vec<Game>,
    pub selected: String,
    pub steamcmd: String,
    pub game_url: String,
    pub steamcmd_url: String,
}

#[derive(Clone, Debug)]
pub struct LocalMod {
    pub folder: String,
    pub path: String,
    pub name: String,
    pub author: String,
    pub package_id: String,
    pub versions: String,
    pub item_id: String,
    pub issue: String,
}

#[derive(Clone, Debug)]
pub struct WorkshopItem {
    pub id: String,
    pub title: String,
    pub preview: String,
    pub description: String,
    pub updated: i64,
}

pub struct SearchPage {
    pub items: Vec<WorkshopItem>,
    pub has_next: bool,
}

#[derive(Clone, Debug)]
pub struct OrderMod {
    pub id: String,
    pub name: String,
    pub source: String,
}

pub struct ModOrder {
    pub mods: Vec<OrderMod>,
    pub active: Vec<String>,
    pub config_path: String,
    pub revision: String,
    pub warnings: Vec<String>,
}

pub struct OrderCheck {
    pub active: Vec<String>,
    pub problems: Vec<String>,
    pub warnings: Vec<String>,
}

pub fn mod_order(game: String) -> Result<ModOrder> {
    crate::mod_order::read(&game)
}
pub fn organize_mods(game: String, active: Vec<String>, sort: bool) -> Result<OrderCheck> {
    crate::mod_order::organize(&game, active, sort)
}
pub fn save_mod_order(game: String, active: Vec<String>, revision: String) -> Result<ModOrder> {
    crate::mod_order::save(&game, active, &revision)
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TaskKind {
    Scan,
    InstallGame,
    InstallSteamcmd,
    InstallMod,
}

#[derive(Clone, Debug)]
pub struct TaskRequest {
    pub id: String,
    pub kind: TaskKind,
    /// Scan root, component destination or game installation directory.
    pub target: String,
    /// Component URL or Workshop ID.
    pub source: String,
    /// Existing local folder selected for update.
    pub folder: String,
    pub steamcmd: String,
}

#[derive(Clone, Debug)]
pub struct TaskEvent {
    pub stage: String,
    pub progress: Option<f64>,
    pub done: bool,
    pub error: bool,
}

pub fn library() -> Result<Library> {
    crate::catalog::library()
}
pub fn select_game(path: String) -> Result<()> {
    crate::catalog::select(&path)
}
pub fn register_game(path: String) -> Result<Game> {
    crate::catalog::register(&path)
}
pub fn set_steamcmd(path: String) -> Result<()> {
    crate::catalog::set_cmd(&path)
}
pub fn set_game_url(url: String) -> Result<()> {
    crate::catalog::set_url(&url)
}
pub fn set_steamcmd_url(url: String) -> Result<()> {
    crate::catalog::set_cmd_url(&url)
}
pub fn launch_game(path: String) -> Result<()> {
    crate::catalog::launch(&path)
}
pub fn list_mods(game: String) -> Result<Vec<LocalMod>> {
    crate::localmods::list(&game)
}
pub fn link_mod(game: String, folder: String, item_id: String) -> Result<()> {
    crate::localmods::link(&game, &folder, &item_id)
}
pub fn uninstall_mod(game: String, folder: String) -> Result<()> {
    crate::localmods::uninstall(&game, &folder)
}
pub fn search_workshop(query: String, page: u32) -> Result<SearchPage> {
    crate::workshop::search(&query, page)
}
pub fn task(request: TaskRequest, sink: StreamSink<TaskEvent>) {
    crate::install::start(request, move |e| {
        let _ = sink.add(e);
    });
}
pub fn cancel_scan(id: String) {
    crate::install::cancel_scan(&id);
}
pub fn choose_directory() -> Option<String> {
    rfd::FileDialog::new()
        .pick_folder()
        .map(|p| p.to_string_lossy().into_owned())
}
