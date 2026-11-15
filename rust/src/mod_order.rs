use crate::{
    api::{ModOrder, OrderCheck, OrderMod},
    discovery, storage,
};
use anyhow::{bail, ensure, Context, Result};
use roxmltree::Node;
use std::{
    collections::{BTreeSet, HashMap, HashSet},
    fs,
    hash::{DefaultHasher, Hash, Hasher},
    io::Write,
    path::{Path, PathBuf},
};

const CORE: &str = "ludeon.rimworld";
struct Rules {
    item: OrderMod,
    requires: Vec<String>,
    before: Vec<String>,
    after: Vec<String>,
    incompatible: Vec<String>,
    versions: Vec<String>,
}
fn child<'a, 'i>(node: Node<'a, 'i>, name: &str) -> Option<Node<'a, 'i>> {
    node.children()
        .find(|n| n.is_element() && n.tag_name().name().eq_ignore_ascii_case(name))
}
fn field(node: Node<'_, '_>, name: &str) -> String {
    child(node, name)
        .and_then(|n| n.text())
        .unwrap_or("")
        .trim()
        .to_owned()
}
fn values(node: Node<'_, '_>) -> Vec<String> {
    node.children()
        .filter(|n| n.has_tag_name("li"))
        .filter_map(|n| n.text())
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect()
}
fn versioned(node: Node<'_, '_>, tag: &str, version: &str) -> Vec<String> {
    let selected = child(node, &format!("{tag}ByVersion"))
        .and_then(|v| child(v, &format!("v{version}")))
        .or_else(|| child(node, tag));
    selected.map(values).unwrap_or_default()
}
fn metadata(path: &Path, source: &str, version: &str) -> Result<Rules> {
    let xml = path.join("About/About.xml");
    storage::plain(&xml)?;
    let text = fs::read_to_string(&xml)?;
    let doc = roxmltree::Document::parse(text.trim_start_matches('\u{feff}'))?;
    let node = doc.root_element();
    let id = field(node, "packageId").to_lowercase();
    ensure!(!id.is_empty(), "缺少 packageId");
    let name = field(node, "name");
    let dependency_node = child(node, "modDependenciesByVersion")
        .and_then(|v| child(v, &format!("v{version}")))
        .or_else(|| child(node, "modDependencies"));
    let requires = dependency_node
        .into_iter()
        .flat_map(|n| n.children().filter(|n| n.has_tag_name("li")))
        .map(|n| field(n, "packageId").to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    let mut before = versioned(node, "loadBefore", version);
    before.extend(versioned(node, "forceLoadBefore", version));
    let mut after = versioned(node, "loadAfter", version);
    after.extend(versioned(node, "forceLoadAfter", version));
    Ok(Rules {
        item: OrderMod {
            id,
            name: if name.is_empty() {
                path.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .into_owned()
            } else {
                name
            },
            source: source.to_owned(),
        },
        requires,
        before,
        after,
        incompatible: versioned(node, "incompatibleWith", version),
        versions: child(node, "supportedVersions")
            .map(values)
            .unwrap_or_default(),
    })
}
fn inventory(game: &str) -> Result<(Vec<Rules>, Vec<String>, String)> {
    let g = discovery::game(Path::new(game), false)?;
    let version = g.version.split('.').take(2).collect::<Vec<_>>().join(".");
    let root = Path::new(&g.path);
    let mut dirs = vec![
        (root.join("Data"), "游戏本体 / DLC"),
        (root.join("Mods"), "本地 Mod"),
    ];
    for s in discovery::steam_installations()
        .iter()
        .filter(|s| s.path.eq_ignore_ascii_case(&g.path))
    {
        if let Ok(steam) = steamlocate::SteamDir::locate() {
            for lib in steam.libraries().into_iter().flatten().flatten() {
                if let Some(Ok(app)) = lib.app(294100) {
                    if storage::canonical(&lib.resolve_app_dir(&app))
                        .is_ok_and(|p| p.to_string_lossy().eq_ignore_ascii_case(&s.path))
                    {
                        dirs.push((
                            lib.path().join("steamapps/workshop/content/294100"),
                            "Steam 订阅",
                        ));
                    }
                }
            }
        }
    }
    let mut all = Vec::<Rules>::new();
    let mut warnings = Vec::new();
    for (directory, source) in dirs {
        if !directory.is_dir() {
            continue;
        }
        storage::plain(&directory)?;
        let mut paths = directory
            .read_dir()?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| {
                p.is_dir()
                    && !p
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy()
                        .starts_with(".rimlauncher")
            })
            .collect::<Vec<_>>();
        paths.sort();
        for path in paths {
            if !path.join("About/About.xml").is_file() {
                continue;
            }
            let loaded = (|| -> Result<Rules> {
                storage::plain(&path)?;
                storage::plain(&path.join("About"))?;
                metadata(&path, source, &version)
            })();
            match loaded {
                Ok(mut r) => {
                    if source == "Steam 订阅" {
                        let item = &mut r.item;
                        if all.iter().any(|r| r.item.id == item.id) {
                            item.id.push_str("_steam");
                        }
                    }
                    all.push(r);
                }
                Err(e) => warnings.push(format!("无法读取 {}：{e}", path.display())),
            }
        }
    }
    Ok((all, warnings, version))
}
fn base(id: &str) -> &str {
    id.strip_suffix("_steam").unwrap_or(id)
}
fn check(rules: &[Rules], requested: Vec<String>, sort: bool, version: &str) -> OrderCheck {
    let active = requested
        .into_iter()
        .map(|id| id.trim().to_lowercase())
        .collect::<Vec<_>>();
    let mut problems = Vec::new();
    let mut warnings = Vec::new();
    let mut seen = HashSet::new();
    let mut selected = Vec::new();
    for id in &active {
        if !seen.insert(base(id).to_owned()) {
            problems.push(format!("重复启用同一包：{id}"));
        }
        let matched = rules
            .iter()
            .filter(|r| r.item.id == *id)
            .collect::<Vec<_>>();
        if matched.len() != 1 {
            problems.push(if matched.is_empty() {
                format!("未找到已启用的 Mod：{id}")
            } else {
                format!("包 ID 对应多个目录：{id}")
            });
            selected.push(None);
        } else {
            selected.push(Some(matched[0]));
        }
    }
    if !active.iter().any(|id| base(id) == CORE) {
        problems.push("必须启用游戏本体 Core".to_owned());
    }
    let positions = active
        .iter()
        .enumerate()
        .map(|(i, id)| (base(id).to_owned(), i))
        .collect::<HashMap<_, _>>();
    let mut edges = vec![BTreeSet::new(); active.len()];
    for (i, entry) in selected.iter().enumerate() {
        let Some(r) = entry else { continue };
        let item = &r.item;
        if !r.versions.is_empty() && !r.versions.iter().any(|v| v == version) {
            warnings.push(format!("{} 未声明支持游戏版本 {version}", item.name));
        }
        for dep in &r.requires {
            if let Some(&j) = positions.get(base(dep)) {
                if j != i {
                    edges[j].insert(i);
                }
            } else {
                problems.push(format!("{} 缺少已启用的依赖：{dep}", item.name));
            }
        }
        for other in &r.before {
            if let Some(&j) = positions.get(base(other)) {
                edges[i].insert(j);
            }
        }
        for other in &r.after {
            if let Some(&j) = positions.get(base(other)) {
                edges[j].insert(i);
            }
        }
        for other in &r.incompatible {
            if let Some(&j) = positions.get(base(other)) {
                if i != j {
                    problems.push(format!("{} 与 {} 不能同时启用", item.name, active[j]));
                }
            }
        }
    }
    // Core and expansions precede regular Mods. Explicit before-Core rules
    // (including transitive prerequisite chains) take precedence.
    if let Some(&core) = positions.get(CORE) {
        for (i, entry) in selected.iter().enumerate() {
            if i != core && entry.is_some_and(|r| r.item.source == "游戏本体 / DLC") {
                edges[core].insert(i);
            }
        }
    }
    let declared = edges.clone();
    for (i, entry) in selected.iter().enumerate() {
        if !entry.is_some_and(|r| r.item.source == "游戏本体 / DLC") {
            continue;
        }
        for (j, other) in selected.iter().enumerate() {
            if other.is_some_and(|r| r.item.source != "游戏本体 / DLC") && !reaches(&declared, j, i)
            {
                edges[i].insert(j);
            }
        }
    }
    let mut indegree = vec![0; active.len()];
    for next in &edges {
        for &j in next {
            indegree[j] += 1;
        }
    }
    let mut ready = indegree
        .iter()
        .enumerate()
        .filter_map(|(i, &degree)| (degree == 0).then_some(i))
        .collect::<BTreeSet<_>>();
    let mut sorted = Vec::new();
    while let Some(i) = ready.pop_first() {
        sorted.push(active[i].clone());
        for &j in &edges[i] {
            indegree[j] -= 1;
            if indegree[j] == 0 {
                ready.insert(j);
            }
        }
    }
    if sorted.len() != active.len() {
        let involved = indegree
            .iter()
            .enumerate()
            .filter(|(_, v)| **v > 0)
            .map(|(i, _)| active[i].as_str())
            .collect::<Vec<_>>()
            .join("、");
        problems.push(format!("排序规则形成循环或受循环阻塞：{involved}"));
    }
    if !sort {
        for (i, next) in edges.iter().enumerate() {
            for &j in next {
                if i >= j {
                    problems.push(format!("顺序要求：{} 必须在 {} 之前", active[i], active[j]));
                }
            }
        }
    }
    problems.sort();
    problems.dedup();
    OrderCheck {
        active: if sort && sorted.len() == active.len() {
            sorted
        } else {
            active
        },
        problems,
        warnings,
    }
}
fn reaches(edges: &[BTreeSet<usize>], from: usize, to: usize) -> bool {
    let mut pending = vec![from];
    let mut seen = HashSet::new();
    while let Some(i) = pending.pop() {
        if i == to {
            return true;
        }
        if seen.insert(i) {
            pending.extend(edges[i].iter().copied());
        }
    }
    false
}
#[cfg(test)]
fn config_path() -> Result<PathBuf> {
    Ok(storage::data_dir()?.join("Config/ModsConfig.xml"))
}
#[cfg(not(test))]
fn config_path() -> Result<PathBuf> {
    let profile = std::env::var_os("USERPROFILE").context("无法定位用户存档目录")?;
    Ok(PathBuf::from(profile)
        .join("AppData/LocalLow/Ludeon Studios/RimWorld by Ludeon Studios/Config/ModsConfig.xml"))
}
fn read_bytes(config: &Path) -> Result<Vec<u8>> {
    match fs::read(config) {
        Ok(bytes) => Ok(bytes),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(e) => Err(e.into()),
    }
}
fn revision(bytes: &[u8]) -> String {
    let mut h = DefaultHasher::new();
    bytes.hash(&mut h);
    format!("{:016x}", h.finish())
}
fn active_ids(bytes: &[u8]) -> Result<Vec<String>> {
    if bytes.is_empty() {
        return Ok(vec![CORE.to_owned()]);
    }
    let text = std::str::from_utf8(bytes)?.trim_start_matches('\u{feff}');
    let doc = roxmltree::Document::parse(text).context("ModsConfig.xml 格式无效")?;
    ensure!(
        doc.root_element().has_tag_name("ModsConfigData"),
        "无法识别的 ModsConfig.xml"
    );
    Ok(child(doc.root_element(), "activeMods")
        .map(values)
        .unwrap_or_default())
}
pub fn read(game: &str) -> Result<ModOrder> {
    read_at(game, &config_path()?)
}
pub(super) fn read_at(game: &str, path: &Path) -> Result<ModOrder> {
    let (rules, mut warnings, version) = inventory(game)?;
    let bytes = read_bytes(path)?;
    let active = active_ids(&bytes)?;
    let check = check(&rules, active.clone(), false, &version);
    warnings.extend(check.warnings);
    warnings.extend(check.problems);
    Ok(ModOrder {
        mods: rules.into_iter().map(|r| r.item).collect(),
        active,
        config_path: path.display().to_string(),
        revision: revision(&bytes),
        warnings,
    })
}
pub fn organize(game: &str, active: Vec<String>, sort: bool) -> Result<OrderCheck> {
    let (rules, notes, version) = inventory(game)?;
    let mut result = check(&rules, active, sort, &version);
    result.warnings.extend(notes);
    Ok(result)
}
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
fn replace_active(bytes: &[u8], active: &[String], version: &str) -> Result<String> {
    let block = format!(
        "<activeMods>\n{}\n  </activeMods>",
        active
            .iter()
            .map(|id| format!("    <li>{}</li>", xml_escape(id)))
            .collect::<Vec<_>>()
            .join("\n")
    );
    if bytes.is_empty() {
        return Ok(format!("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<ModsConfigData>\n  <version>{}</version>\n  {block}\n</ModsConfigData>\n",xml_escape(version)));
    }
    let original = std::str::from_utf8(bytes)?.trim_start_matches('\u{feff}');
    let doc = roxmltree::Document::parse(original)?;
    let root = doc.root_element();
    if let Some(node) = child(root, "activeMods") {
        let range = node.range();
        Ok(format!(
            "{}{}{}",
            &original[..range.start],
            block,
            &original[range.end..]
        ))
    } else {
        let range = root.range();
        if original[range.clone()].trim_end().ends_with("/>") {
            return Ok(format!(
                "{}>\n  {block}\n</ModsConfigData>{}",
                &original[..range.end - 2],
                &original[range.end..]
            ));
        }
        let closing = original
            .rfind("</ModsConfigData>")
            .context("ModsConfigData 缺少结束标签")?;
        Ok(format!(
            "{}  {block}\n{}",
            &original[..closing],
            &original[closing..]
        ))
    }
}
fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    let mut temp = tempfile::NamedTempFile::new_in(path.parent().context("无配置父目录")?)?;
    temp.write_all(bytes)?;
    temp.as_file().sync_all()?;
    temp.persist(path)?;
    Ok(())
}
#[cfg(not(test))]
fn ensure_game_closed() -> Result<()> {
    use std::{
        mem::size_of,
        os::windows::io::{FromRawHandle, OwnedHandle},
    };
    use windows_sys::Win32::{Foundation::INVALID_HANDLE_VALUE, System::Diagnostics::ToolHelp::*};
    let handle = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    ensure!(handle != INVALID_HANDLE_VALUE, "无法检查游戏运行状态");
    let _owned = unsafe { OwnedHandle::from_raw_handle(handle) };
    let mut entry = PROCESSENTRY32W {
        dwSize: size_of::<PROCESSENTRY32W>() as u32,
        ..Default::default()
    };
    let mut ok = unsafe { Process32FirstW(handle, &mut entry) };
    while ok != 0 {
        let len = entry
            .szExeFile
            .iter()
            .position(|&c| c == 0)
            .unwrap_or(entry.szExeFile.len());
        let exe = String::from_utf16_lossy(&entry.szExeFile[..len]);
        ensure!(
            !["rimworld.exe", "rimworldwin64.exe"].contains(&exe.to_lowercase().as_str()),
            "请关闭正在运行的 RimWorld，再保存加载顺序"
        );
        ok = unsafe { Process32NextW(handle, &mut entry) };
    }
    Ok(())
}
pub fn save(game: &str, active: Vec<String>, expected: &str) -> Result<ModOrder> {
    save_at(game, active, expected, &config_path()?)
}
pub(super) fn save_at(
    game: &str,
    active: Vec<String>,
    expected: &str,
    path: &Path,
) -> Result<ModOrder> {
    #[cfg(not(test))]
    ensure_game_closed()?;
    let _guard = storage::lock(&path.to_string_lossy())?;
    let current = read_bytes(path)?;
    ensure!(
        revision(&current) == expected,
        "游戏配置已被其他程序修改，请重新读取后再保存"
    );
    let result = organize(game, active, false)?;
    if !result.problems.is_empty() {
        bail!("{}", result.problems.join("\n"));
    }
    let game_version = discovery::game(Path::new(game), false)?.version;
    let text = replace_active(&current, &result.active, &game_version)?;
    let parent = path.parent().context("无配置父目录")?;
    fs::create_dir_all(parent)?;
    if !current.is_empty() {
        storage::plain(path)?;
        atomic_write(&path.with_extension("xml.rimlauncher.bak"), &current)?;
    }
    ensure!(
        read_bytes(path)? == current,
        "游戏配置在保存期间发生变化，请重新读取"
    );
    atomic_write(path, text.as_bytes()).context("保存加载顺序失败")?;
    read_at(game, path)
}
#[cfg(test)]
mod tests {
    use super::*;
    fn game() -> Result<(tempfile::TempDir, String)> {
        let temp = tempfile::tempdir()?;
        fs::create_dir_all(temp.path().join("Data/Core/About"))?;
        fs::create_dir_all(temp.path().join("Mods"))?;
        fs::write(temp.path().join("RimWorld.exe"), "fixture")?;
        fs::write(temp.path().join("Version.txt"), "1.7.4990")?;
        fs::write(temp.path().join("Data/Core/About/About.xml"),"<ModMetaData><packageId>Ludeon.RimWorld</packageId><forceLoadBefore><li>ludeon.rimworld.royalty</li></forceLoadBefore></ModMetaData>")?;
        let path = temp.path().display().to_string();
        Ok((temp, path))
    }
    fn add(root: &Path, folder: &str, id: &str, rules: &str) -> Result<()> {
        let path = root.join(folder).join("About");
        fs::create_dir_all(&path)?;
        fs::write(
            path.join("About.xml"),
            format!(
                "<ModMetaData><name>{id}</name><packageId>{id}</packageId>{rules}</ModMetaData>"
            ),
        )?;
        Ok(())
    }
    fn ids(values: &[&str]) -> Vec<String> {
        values.iter().map(|s| (*s).to_owned()).collect()
    }
    #[test]
    fn sorts_dependencies_core_dlc_and_pre_core_mods() -> Result<()> {
        let (temp, path) = game()?;
        add(
            temp.path(),
            "Data/Royalty",
            "ludeon.rimworld.royalty",
            "<forceLoadAfter><li>ludeon.rimworld</li></forceLoadAfter>",
        )?;
        add(
            temp.path(),
            "Mods/Harmony",
            "brrainz.harmony",
            "<loadBefore><li>Ludeon.RimWorld</li></loadBefore>",
        )?;
        add(
            temp.path(),
            "Mods/Speed",
            "speed.mod",
            "<modDependencies><li><packageId>brrainz.harmony</packageId></li></modDependencies>",
        )?;
        let input = ids(&[
            "speed.mod",
            "ludeon.rimworld.royalty",
            CORE,
            "brrainz.harmony",
        ]);
        assert!(!organize(&path, input.clone(), false)?.problems.is_empty());
        let out = organize(&path, input, true)?;
        assert!(out.problems.is_empty(), "{:?}", out.problems);
        assert_eq!(
            out.active,
            ids(&[
                "brrainz.harmony",
                CORE,
                "ludeon.rimworld.royalty",
                "speed.mod"
            ])
        );
        assert!(organize(&path, out.active, false)?.problems.is_empty());
        Ok(())
    }
    #[test]
    fn stable_sort_and_versioned_override() -> Result<()> {
        let (temp, path) = game()?;
        add(temp.path(),"Mods/A","a","<loadAfter><li>b</li></loadAfter><loadAfterByVersion><v1.7><li>c</li></v1.7></loadAfterByVersion><modDependencies><li><packageId>absent</packageId></li></modDependencies><modDependenciesByVersion><v1.7><li><packageId>c</packageId></li></v1.7></modDependenciesByVersion>")?;
        add(temp.path(), "Mods/B", "b", "")?;
        add(temp.path(), "Mods/C", "c", "")?;
        let result = organize(&path, ids(&[CORE, "a", "b", "c"]), true)?;
        assert!(result.problems.is_empty(), "{:?}", result.problems);
        assert_eq!(result.active, ids(&[CORE, "b", "c", "a"]));
        assert_eq!(
            organize(&path, result.active.clone(), true)?.active,
            result.active
        );
        Ok(())
    }
    #[test]
    fn detects_cycles_missing_incompatibilities_and_duplicates() -> Result<()> {
        let (temp, path) = game()?;
        add(temp.path(),"Mods/A","a","<loadBefore><li>b</li></loadBefore><modDependencies><li><packageId>missing</packageId></li></modDependencies><incompatibleWith><li>b</li></incompatibleWith>")?;
        add(
            temp.path(),
            "Mods/B",
            "b",
            "<forceLoadBefore><li>a</li></forceLoadBefore>",
        )?;
        let original = ids(&[CORE, "a", "b"]);
        let result = organize(&path, original.clone(), true)?;
        assert_eq!(result.active, original);
        assert!(result.problems.iter().any(|s| s.contains("循环")));
        assert!(result.problems.iter().any(|s| s.contains("missing")));
        assert!(result.problems.iter().any(|s| s.contains("不能同时")));
        assert!(organize(&path, ids(&[CORE, CORE]), true)?
            .problems
            .iter()
            .any(|s| s.contains("重复")));
        assert!(organize(&path, ids(&["a"]), true)?
            .problems
            .iter()
            .any(|s| s.contains("Core")));
        Ok(())
    }
    #[test]
    fn saves_actual_xml_preserves_other_fields_and_rejects_stale_edits() -> Result<()> {
        let (temp, path) = game()?;
        add(temp.path(), "Mods/A", "a", "")?;
        let config = temp.path().join("Config/ModsConfig.xml");
        fs::create_dir_all(config.parent().unwrap())?;
        let original = r#"<?xml version="1.0"?><ModsConfigData><version>keep-this</version><!--keep--><activeMods><li>ludeon.rimworld</li></activeMods><knownExpansions><li>sample.expansion</li></knownExpansions><future value="true"/></ModsConfigData>"#;
        fs::write(&config, original)?;
        let snapshot = read_at(&path, &config)?;
        let result = save_at(&path, ids(&[CORE, "a"]), &snapshot.revision, &config)?;
        assert_eq!(result.active, ids(&[CORE, "a"]));
        let text = fs::read_to_string(&config)?;
        assert!(text.contains("<version>keep-this</version><!--keep-->"));
        assert!(text.contains(
            r#"<knownExpansions><li>sample.expansion</li></knownExpansions><future value="true"/>"#
        ));
        assert_eq!(
            fs::read_to_string(config.with_extension("xml.rimlauncher.bak"))?,
            original
        );
        assert!(save_at(&path, ids(&[CORE]), &snapshot.revision, &config).is_err());
        assert_eq!(fs::read_to_string(&config)?, text);
        assert!(save_at(&path, ids(&[CORE, "missing"]), &result.revision, &config).is_err());
        assert_eq!(fs::read_to_string(&config)?, text);
        use std::os::windows::fs::OpenOptionsExt;
        let locked = fs::OpenOptions::new()
            .read(true)
            .share_mode(1)
            .open(&config)?;
        assert!(save_at(&path, ids(&[CORE]), &result.revision, &config).is_err());
        drop(locked);
        assert_eq!(fs::read_to_string(&config)?, text);
        Ok(())
    }
    #[test]
    fn creates_missing_config_and_rejects_corrupt_xml() -> Result<()> {
        let (temp, path) = game()?;
        let config = temp.path().join("Config/ModsConfig.xml");
        let snapshot = read_at(&path, &config)?;
        assert_eq!(snapshot.active, ids(&[CORE]));
        let saved = save_at(&path, snapshot.active, &snapshot.revision, &config)?;
        assert_eq!(saved.active, ids(&[CORE]));
        fs::write(&config, "<broken>")?;
        assert!(read_at(&path, &config).is_err());
        Ok(())
    }
    #[test]
    #[ignore = "read-only verification using the development machine's game and config"]
    fn local_order_metadata() -> Result<()> {
        let path = r"G:\GameSpace\Game\RimWorld.v4990\RimWorld";
        let config = PathBuf::from(std::env::var("USERPROFILE")?).join(
            "AppData/LocalLow/Ludeon Studios/RimWorld by Ludeon Studios/Config/ModsConfig.xml",
        );
        let state = read_at(path, &config)?;
        let result = organize(path, state.active.clone(), true)?;
        assert!(result.problems.is_empty(), "{:?}", result.problems);
        assert_eq!(
            result.active.first().map(String::as_str),
            Some("brrainz.harmony")
        );
        assert!(
            result.active.iter().position(|s| s == CORE).unwrap()
                < result
                    .active
                    .iter()
                    .position(|s| s == "thegoosebehindtheslaughter.noforcedslowdown")
                    .unwrap()
        );
        println!(
            "Read-only order checked: {} active Mods",
            result.active.len()
        );
        Ok(())
    }
}
