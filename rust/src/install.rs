use crate::{
    api::{TaskEvent, TaskKind, TaskRequest},
    catalog, discovery, localmods, storage, workshop,
};
use anyhow::{bail, ensure, Context, Result};
use std::{
    collections::HashMap,
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom, Write},
    os::windows::process::CommandExt,
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, LazyLock, Mutex,
    },
    time::{Duration, Instant},
};
use wait_timeout::ChildExt;

pub const STEAM_URL: &str = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip";
static SCANS: LazyLock<Mutex<HashMap<String, Arc<AtomicBool>>>> = LazyLock::new(Default::default);
type Report<'a> = dyn Fn(String, Option<f64>) + 'a;
pub fn cancel_scan(id: &str) {
    if let Some(v) = SCANS.lock().unwrap().get(id) {
        v.store(true, Ordering::Relaxed);
    }
}
pub fn start(r: TaskRequest, send: impl Fn(TaskEvent) + Send + 'static) {
    let cancel = Arc::new(AtomicBool::new(false));
    if r.kind == TaskKind::Scan {
        SCANS.lock().unwrap().insert(r.id.clone(), cancel.clone());
    }
    std::thread::spawn(move || {
        let report = |stage, progress| {
            send(TaskEvent {
                stage,
                progress,
                done: false,
                error: false,
            })
        };
        report("准备中".into(), None);
        let result = (|| -> Result<()> {
            match r.kind {
                TaskKind::Scan => {
                    let lib = catalog::library()?;
                    let (games, cmd) = discovery::scan(
                        &r.target,
                        &lib.games,
                        &lib.steamcmd,
                        || cancel.load(Ordering::Relaxed),
                        |s| report(s, None),
                    )?;
                    catalog::scanned(games, cmd, !r.target.is_empty())
                }
                TaskKind::InstallGame | TaskKind::InstallSteamcmd => component(&r, &report),
                TaskKind::InstallMod => install_mod(&r, &report),
            }
        })();
        if r.kind == TaskKind::Scan {
            SCANS.lock().unwrap().remove(&r.id);
        }
        let cancelled = cancel.load(Ordering::Relaxed);
        let stage = match &result {
            Ok(_) => "已完成".to_owned(),
            Err(e) => format!("{e:#}"),
        };
        send(TaskEvent {
            stage,
            progress: result.is_ok().then_some(1.0),
            done: true,
            error: result.is_err() && !cancelled,
        });
    });
}
fn download(url: &str, target: &Path, report: &Report) -> Result<()> {
    let mut resp = workshop::client(Duration::from_secs(3600))?
        .get(storage::url(url)?)
        .send()
        .context("连接下载源失败")?
        .error_for_status()?;
    let size = resp.content_length();
    let mut bytes = 0u64;
    let mut file = File::create(target)?;
    let mut buffer = [0u8; 65536];
    let mut last = Instant::now();
    report("正在下载压缩包".into(), None);
    loop {
        let read = resp.read(&mut buffer).context("下载中断")?;
        if read == 0 {
            break;
        }
        file.write_all(&buffer[..read])?;
        bytes += read as u64;
        if last.elapsed() > Duration::from_millis(160) {
            report(
                format!("已下载 {:.1} MB", bytes as f64 / 1048576.),
                size.filter(|&n| n > 0).map(|n| bytes as f64 / n as f64),
            );
            last = Instant::now();
        }
    }
    ensure!(size.is_none_or(|n| n == bytes), "下载不完整");
    file.sync_all()?;
    Ok(())
}
fn extract(zip_path: &Path, dir: &Path) -> Result<()> {
    let mut zip =
        zip::ZipArchive::new(File::open(zip_path)?).context("下载内容不是支持的 ZIP 压缩包")?;
    fs::create_dir(dir)?;
    for i in 0..zip.len() {
        let mut e = zip.by_index(i)?;
        ensure!(!e.is_symlink(), "压缩包包含链接");
        let enclosed = e.enclosed_name().context("压缩包路径无效")?;
        for part in enclosed.components() {
            match part {
                Component::Normal(s) => storage::leaf(s.to_str().context("压缩包文件名无效")?)?,
                Component::CurDir => (),
                _ => bail!("压缩包路径超出目标目录"),
            }
        }
        let path = dir.join(enclosed);
        if e.is_dir() {
            fs::create_dir_all(path)?;
        } else {
            fs::create_dir_all(path.parent().context("无效的文件路径")?)?;
            let mut out = File::create_new(&path).context("压缩包包含重复或无效文件名")?;
            io::copy(&mut e, &mut out)?;
        }
    }
    Ok(())
}
fn validate_empty(target: &Path) -> Result<()> {
    ensure!(
        target.is_absolute() && target.parent().is_some(),
        "请选择完整的安装目录"
    );
    if target.try_exists()? {
        storage::plain(target)?;
        ensure!(
            target.is_dir() && target.read_dir()?.next().is_none(),
            "目标目录已有文件。可以登记现有安装，或另选空目录。"
        );
    }
    Ok(())
}
pub(super) fn component(r: &TaskRequest, report: &Report) -> Result<()> {
    let target = Path::new(&r.target);
    validate_empty(target)?;
    let steam = r.kind == TaskKind::InstallSteamcmd;
    let parent = target.parent().context("请选择独立的安装目录")?;
    fs::create_dir_all(parent)?;
    let _lock = storage::lock(&format!(
        "install:{}",
        storage::canonical(parent)?
            .join(target.file_name().context("目录无效")?)
            .display()
    ))?;
    validate_empty(target)?;
    let temp = tempfile::Builder::new()
        .prefix(".rimlauncher-install-")
        .tempdir_in(parent)?;
    let archive = temp.path().join("download.zip");
    download(
        if steam && r.source.is_empty() {
            STEAM_URL
        } else {
            &r.source
        },
        &archive,
        report,
    )?;
    report("正在解压并验证".into(), None);
    let extracted = temp.path().join("unpacked");
    extract(&archive, &extracted)?;
    let mut candidates = vec![];
    for entry in walkdir::WalkDir::new(&extracted).max_depth(12) {
        let e = entry?;
        if !e.file_type().is_dir() {
            continue;
        }
        if if steam {
            discovery::cmd(e.path()).is_some()
        } else {
            discovery::game(e.path(), false).is_ok()
        } {
            candidates.push(e.into_path());
        }
    }
    ensure!(
        candidates.len() == 1,
        "压缩包中需要恰好一个可识别的安装目录"
    );
    let candidate = &candidates[0];
    if steam {
        report("正在初始化 SteamCMD".into(), None);
        run_cmd(&candidate.join("steamcmd.exe"), &["+quit"], None, report)?;
        ensure!(
            candidate.join("steamclient.dll").is_file(),
            "SteamCMD 初始化未完成"
        );
    }
    validate_empty(target)?;
    let existed = target.exists();
    if existed {
        fs::remove_dir(target)?;
    }
    if let Err(e) = fs::rename(candidate, target) {
        if existed {
            let _ = fs::create_dir(target);
        }
        return Err(e).context("提交安装目录失败");
    }
    if steam {
        catalog::set_cmd(&r.target)
    } else {
        catalog::register(&r.target).map(|_| ())
    }
}
fn run_cmd(exe: &Path, args: &[&str], item: Option<&str>, report: &Report) -> Result<()> {
    let mut output = tempfile::tempfile()?;
    let log = output.try_clone()?;
    let mut child = Command::new(exe)
        .current_dir(exe.parent().context("SteamCMD 路径无效")?)
        .args(args)
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log)
        .creation_flags(0x08000000)
        .spawn()
        .context("无法启动 SteamCMD")?;
    let tree = match crate::process_tree::ProcessTree::attach(&child) {
        Ok(job) => job,
        Err(e) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(e).context("无法跟踪 SteamCMD 进程");
        }
    };
    let start = Instant::now();
    let mut last_size = 0;
    let status = loop {
        if let Some(s) = child.wait_timeout(Duration::from_millis(700))? {
            break s;
        }
        if start.elapsed() > Duration::from_secs(1800) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("SteamCMD 超时，请检查网络后重试");
        }
        let size = output.metadata()?.len();
        if size > last_size {
            report(
                if item.is_some() {
                    "SteamCMD 正在下载或校验 Mod"
                } else {
                    "SteamCMD 正在初始化"
                }
                .into(),
                None,
            );
            last_size = size;
        }
    };
    while tree.active()? {
        ensure!(
            start.elapsed() < Duration::from_secs(1800),
            "SteamCMD 子进程超时"
        );
        std::thread::sleep(Duration::from_millis(400));
    }
    output.seek(SeekFrom::Start(0))?;
    let mut data = Vec::new();
    output.read_to_end(&mut data)?;
    let body = String::from_utf8_lossy(&data);
    let lower = body.to_lowercase();
    let success = item.is_none_or(|id| lower.contains(&format!("success. downloaded item {id} ")));
    let updated = status.code() == Some(7) && lower.contains("update complete");
    if !(status.success() || updated)
        || !success
        || lower
            .lines()
            .any(|l| l.contains("error!") || l.contains("failed to download item"))
    {
        let tail = body
            .lines()
            .filter(|l| !l.trim().is_empty())
            .rev()
            .take(5)
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect::<Vec<_>>()
            .join("\n");
        bail!("SteamCMD 未完成操作（{status}）\n{tail}");
    }
    Ok(())
}
pub(super) fn install_mod(r: &TaskRequest, report: &Report) -> Result<()> {
    let id = storage::id(&r.source)?;
    discovery::game(Path::new(&r.target), false)?;
    let exe = discovery::cmd(Path::new(&r.steamcmd)).context("请先在设置中选择或安装 SteamCMD")?;
    report("等待 SteamCMD".into(), None);
    let _lock = storage::lock(&exe.to_string_lossy())?;
    report("正在连接 Steam 创意工坊".into(), None);
    run_cmd(
        &exe,
        &[
            "+login",
            "anonymous",
            "+workshop_download_item",
            "294100",
            id,
            "validate",
            "+quit",
        ],
        Some(id),
        report,
    )?;
    let source: PathBuf = exe
        .parent()
        .unwrap()
        .join("steamapps/workshop/content/294100")
        .join(id);
    report("正在校验并安装 Mod".into(), None);
    localmods::deploy(&r.target, &r.folder, id, &source)
}
