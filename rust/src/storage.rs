use anyhow::{bail, ensure, Context, Result};
use fs2::FileExt;
use serde::{de::DeserializeOwned, Serialize};
use std::hash::{DefaultHasher, Hash, Hasher};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    os::windows::fs::MetadataExt,
    path::{Component, Path, PathBuf},
};

#[cfg(test)]
pub fn data_dir() -> Result<PathBuf> {
    thread_local! { static DIR: tempfile::TempDir = tempfile::tempdir().expect("test settings"); }
    Ok(DIR.with(|dir| dir.path().into()))
}
#[cfg(not(test))]
pub fn data_dir() -> Result<PathBuf> {
    let base = std::env::var_os("RIMLAUNCHER_DATA")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("LOCALAPPDATA").map(|p| PathBuf::from(p).join("RimWorldLauncher"))
        })
        .context("无法定位用户设置目录")?;
    fs::create_dir_all(&base)?;
    Ok(base)
}
pub fn lock(key: &str) -> Result<File> {
    let mut hash = DefaultHasher::new();
    key.to_lowercase().hash(&mut hash);
    let path = data_dir()?.join(format!("{:016x}.lock", hash.finish()));
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)?;
    file.lock_exclusive()?;
    Ok(file)
}
pub fn read_json<T: DeserializeOwned + Default>(path: &Path) -> Result<T> {
    match fs::read(path) {
        Ok(bytes) => Ok(serde_json::from_slice(&bytes).context("配置文件格式无效")?),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(T::default()),
        Err(e) => Err(e.into()),
    }
}
pub fn write_json<T: Serialize>(path: &Path, data: &T) -> Result<()> {
    let mut file = tempfile::NamedTempFile::new_in(path.parent().context("无父目录")?)?;
    serde_json::to_writer_pretty(&mut file, data)?;
    file.flush()?;
    file.as_file().sync_all()?;
    file.persist(path)?;
    Ok(())
}
pub fn canonical(p: &Path) -> Result<PathBuf> {
    dunce::canonicalize(p).with_context(|| format!("无法访问 {}", p.display()))
}
pub fn plain(p: &Path) -> Result<()> {
    let md = fs::symlink_metadata(p)?;
    ensure!(
        md.file_attributes() & 0x400 == 0,
        "此操作不支持链接或重解析目录：{}",
        p.display()
    );
    Ok(())
}
pub fn leaf(s: &str) -> Result<()> {
    ensure!(
        !s.is_empty()
            && !s.ends_with(['.', ' '])
            && !s.contains(['/', '\\', ':', '<', '>', '"', '|', '?', '*'])
            && !s.chars().any(char::is_control)
            && matches!(Path::new(s).components().next(), Some(Component::Normal(_))),
        "无效的目录名"
    );
    let prefix = s.split('.').next().unwrap_or("").to_ascii_uppercase();
    if matches!(
        prefix.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
    ) || (prefix.starts_with("COM") || prefix.starts_with("LPT"))
        && prefix.chars().count() == 4
        && prefix.chars().last().unwrap().is_numeric()
    {
        bail!("保留设备名");
    }
    Ok(())
}
pub fn id(s: &str) -> Result<&str> {
    ensure!(
        !s.starts_with('0') && s.bytes().all(|v| v.is_ascii_digit()) && s.parse::<u64>().is_ok(),
        "请输入有效的创意工坊数字 ID"
    );
    Ok(s)
}
pub fn url(s: &str) -> Result<reqwest::Url> {
    let url = reqwest::Url::parse(s).context("请输入完整的下载网址")?;
    ensure!(
        matches!(url.scheme(), "https" | "http") && url.host_str().is_some(),
        "下载源须为 HTTP 或 HTTPS 直链"
    );
    Ok(url)
}
