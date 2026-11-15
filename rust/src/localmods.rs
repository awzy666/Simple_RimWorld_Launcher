use crate::{api::LocalMod, discovery, storage};
use anyhow::{bail, ensure, Context, Result};
use std::{
    fs::{self, OpenOptions},
    os::windows::fs::OpenOptionsExt,
    path::{Path, PathBuf},
};
use walkdir::WalkDir;

const WORK: &str = ".rimlauncher-transaction";
const LINK: &str = ".rimlauncher-source.json";

fn root(game: &str) -> Result<PathBuf> {
    let g = discovery::game(Path::new(game), false)?;
    let dir = Path::new(&g.path).join("Mods");
    if dir.try_exists()? {
        storage::plain(&dir)?;
        ensure!(dir.is_dir(), "Mods 不是目录");
    }
    Ok(dir)
}
fn folder(root: &Path, name: &str) -> Result<PathBuf> {
    storage::leaf(name)?;
    ensure!(!name.eq_ignore_ascii_case(WORK), "此目录由启动器维护");
    let p = root.join(name);
    if p.try_exists()? {
        storage::plain(&p)?;
    }
    Ok(p)
}
fn metadata(path: &Path) -> Result<LocalMod> {
    storage::plain(path)?;
    let about = path.join("About");
    storage::plain(&about)?;
    let xml = about.join("About.xml");
    storage::plain(&xml)?;
    let data = fs::read_to_string(xml).context("无法读取 About/About.xml")?;
    let doc = roxmltree::Document::parse(data.trim_start_matches('\u{feff}'))
        .context("About.xml 已损坏")?;
    let root = doc.root_element();
    ensure!(
        root.tag_name().name().eq_ignore_ascii_case("ModMetaData"),
        "无效的 ModMetaData"
    );
    let element = |name: &str| {
        root.children()
            .find(|n| n.is_element() && n.tag_name().name().eq_ignore_ascii_case(name))
    };
    let text = |name: &str| {
        element(name)
            .and_then(|n| n.text())
            .unwrap_or("")
            .trim()
            .to_owned()
    };
    let values = |name: &str| {
        element(name)
            .into_iter()
            .flat_map(|n| n.children().filter(|v| v.has_tag_name("li")))
            .filter_map(|n| n.text())
            .collect::<Vec<_>>()
            .join("、")
    };
    let package_id = text("packageId");
    ensure!(!package_id.is_empty(), "About.xml 缺少 packageId");
    let name = text("name");
    let dir = path
        .file_name()
        .context("目录无名称")?
        .to_string_lossy()
        .into_owned();
    let idfile = about.join("PublishedFileId.txt");
    let published = if idfile.is_file() {
        storage::plain(&idfile)?;
        fs::read_to_string(idfile)?
    } else {
        String::new()
    };
    let linked = path.join(LINK);
    let linked_id: String = if linked.is_file() {
        storage::plain(&linked)?;
        storage::read_json(&linked)?
    } else {
        String::new()
    };
    let item_id = [
        published.trim().trim_start_matches('\u{feff}').trim(),
        linked_id.as_str(),
        dir.as_str(),
    ]
    .into_iter()
    .find(|s| storage::id(s).is_ok())
    .unwrap_or("")
    .to_owned();
    let mut author = text("author");
    if author.is_empty() {
        author = values("authors");
    }
    Ok(LocalMod {
        folder: dir.clone(),
        path: path.to_string_lossy().into_owned(),
        name: if name.is_empty() { dir } else { name },
        author,
        package_id,
        versions: values("supportedVersions"),
        item_id,
        issue: String::new(),
    })
}
// Journal is written before either rename. A missing destination with an old tree
// means the process stopped between renames and the original must be restored.
fn recover(mods: &Path) -> Result<()> {
    let work = mods.join(WORK);
    if !work.try_exists()? {
        return Ok(());
    }
    storage::plain(&work)?;
    let journal = work.join("target.json");
    if !journal.try_exists()? && work.read_dir()?.next().is_none() {
        fs::remove_dir(work)?;
        return Ok(());
    }
    ensure!(
        journal.is_file(),
        "发现未识别的事务目录：{}",
        work.display()
    );
    storage::plain(&journal)?;
    let name: String = storage::read_json(&journal)?;
    let target = folder(mods, &name)?;
    let old = work.join("old");
    if old.try_exists()? && !target.try_exists()? {
        storage::plain(&old)?;
        fs::rename(&old, &target).context("恢复原 Mod 失败")?;
    }
    fs::remove_dir_all(work).context("清理 Mod 暂存目录失败")?;
    Ok(())
}
fn inventory(mods: &Path) -> Result<Vec<LocalMod>> {
    if !mods.exists() {
        return Ok(vec![]);
    }
    let mut items = Vec::new();
    for entry in mods.read_dir()? {
        let entry = entry?;
        let p = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.eq_ignore_ascii_case(WORK) || !entry.file_type()?.is_dir() {
            continue;
        }
        items.push(metadata(&p).unwrap_or_else(|e| LocalMod {
            folder: name.clone(),
            path: p.to_string_lossy().into_owned(),
            name,
            author: String::new(),
            package_id: String::new(),
            versions: String::new(),
            item_id: String::new(),
            issue: format!("{e:#}"),
        }));
    }
    items.sort_by_key(|m| m.name.to_lowercase());
    Ok(items)
}
pub fn list(game: &str) -> Result<Vec<LocalMod>> {
    let mods = root(game)?;
    let _guard = storage::lock(&mods.to_string_lossy())?;
    recover(&mods)?;
    inventory(&mods)
}
pub fn link(game: &str, name: &str, id: &str) -> Result<()> {
    storage::id(id)?;
    let mods = root(game)?;
    let _guard = storage::lock(&mods.to_string_lossy())?;
    recover(&mods)?;
    let p = folder(&mods, name)?;
    let item = metadata(&p)?;
    ensure!(
        item.item_id.is_empty() || item.item_id == id,
        "该 Mod 已关联其他工坊条目"
    );
    ensure!(
        !inventory(&mods)?
            .iter()
            .any(|m| m.folder != name && m.item_id == id),
        "另一个目录已关联该条目"
    );
    storage::write_json(&p.join(LINK), &id)
}
fn unlocked(dir: &Path) -> Result<()> {
    for item in WalkDir::new(dir).follow_links(false) {
        let item = item?;
        storage::plain(item.path())?;
        if item.file_type().is_file() {
            OpenOptions::new()
                .read(true)
                .share_mode(0)
                .open(item.path())
                .with_context(|| format!("文件被占用或无法访问：{}", item.path().display()))?;
        }
    }
    Ok(())
}
pub fn uninstall(game: &str, name: &str) -> Result<()> {
    let mods = root(game)?;
    let _guard = storage::lock(&mods.to_string_lossy())?;
    recover(&mods)?;
    let p = folder(&mods, name)?;
    ensure!(p.is_dir(), "Mod 目录不存在");
    unlocked(&p)?;
    let work = begin(&mods, name)?;
    let result = fs::rename(p, work.join("removed")).context("无法移除目录，请关闭占用文件的程序");
    recover(&mods)?;
    result
}
fn begin(mods: &Path, name: &str) -> Result<PathBuf> {
    let work = mods.join(WORK);
    fs::create_dir(&work)?;
    if let Err(e) = storage::write_json(&work.join("target.json"), &name) {
        let _ = fs::remove_dir(&work);
        return Err(e);
    }
    Ok(work)
}
fn copy_tree(src: &Path, dst: &Path) -> Result<()> {
    for item in WalkDir::new(src).follow_links(false) {
        let item = item?;
        storage::plain(item.path())?;
        let dest = dst.join(item.path().strip_prefix(src)?);
        if item.file_type().is_dir() {
            fs::create_dir_all(dest)?;
        } else {
            ensure!(item.file_type().is_file(), "工坊内容含不支持的文件");
            fs::copy(item.path(), dest)?;
        }
    }
    Ok(())
}
pub fn deploy(game: &str, selected: &str, id: &str, source: &Path) -> Result<()> {
    storage::id(id)?;
    let incoming = metadata(source)?;
    ensure!(
        incoming.item_id.is_empty() || incoming.item_id == id,
        "工坊条目与下载内容的 ID 不符"
    );
    let mods = root(game)?;
    let _guard = storage::lock(&mods.to_string_lossy())?;
    fs::create_dir_all(&mods)?;
    storage::plain(&mods)?;
    recover(&mods)?;
    let all = inventory(&mods)?;
    let matching: Vec<_> = all
        .iter()
        .filter(|m| m.item_id == id || m.package_id.eq_ignore_ascii_case(&incoming.package_id))
        .collect();
    ensure!(
        matching.len() <= 1,
        "有多个目录与该条目匹配，请先解决本地重复项"
    );
    let name = if let Some(m) = matching.first() {
        ensure!(
            selected.is_empty() || selected.eq_ignore_ascii_case(&m.folder),
            "选定目录与下载条目不匹配"
        );
        ensure!(
            m.item_id.is_empty() || m.item_id == id,
            "相同包 ID 已关联其他工坊条目"
        );
        m.folder.as_str()
    } else if !selected.is_empty() {
        bail!("所选 Mod 已改变，请刷新列表后重试");
    } else {
        id
    };
    let destination = folder(&mods, name)?;
    if destination.exists() {
        ensure!(!matching.is_empty(), "目标目录已被其他文件占用");
        unlocked(&destination)?;
    }
    let work = begin(&mods, name)?;
    let commit = (|| -> Result<()> {
        let staged = work.join("new");
        copy_tree(source, &staged)?;
        metadata(&staged)?;
        storage::write_json(&staged.join(LINK), &id)?;
        if destination.exists() {
            fs::rename(&destination, work.join("old")).context("无法替换正在使用的 Mod")?;
        }
        fs::rename(staged, &destination).context("无法提交新 Mod")?;
        Ok(())
    })();
    recover(&mods)?;
    commit
}
