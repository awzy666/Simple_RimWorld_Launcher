use crate::{
    api::{SearchPage, WorkshopItem},
    storage,
};
use anyhow::{bail, ensure, Context, Result};
use reqwest::blocking::Client;
use scraper::{Html, Selector};
use serde::Deserialize;
use serde_json::Value;
use std::{collections::HashSet, time::Duration};

pub fn client(timeout: Duration) -> Result<Client> {
    Ok(Client::builder()
        .user_agent("RimWorldLauncher/0.1 (Windows)")
        .connect_timeout(Duration::from_secs(15))
        .timeout(timeout)
        .build()?)
}
fn direct(input: &str) -> Result<Option<String>> {
    if input.starts_with("http://") || input.starts_with("https://") {
        let url = storage::url(input)?;
        ensure!(
            matches!(
                url.host_str(),
                Some("steamcommunity.com" | "www.steamcommunity.com")
            ) && matches!(
                url.path().trim_end_matches('/'),
                "/sharedfiles/filedetails" | "/workshop/filedetails"
            ),
            "请输入 Steam 创意工坊条目链接"
        );
        let id = url
            .query_pairs()
            .find(|(k, _)| k == "id")
            .context("链接缺少工坊 ID")?
            .1
            .into_owned();
        return Ok(Some(storage::id(&id)?.to_owned()));
    }
    if !input.is_empty() && input.bytes().all(|v| v.is_ascii_digit()) {
        return Ok(Some(storage::id(input)?.to_owned()));
    }
    Ok(None)
}
fn results(v: &Value, depth: u8) -> Option<(Vec<String>, bool)> {
    if depth > 12 {
        return None;
    }
    if let (Some(entries), Some(page), Some(pages)) = (
        v.get("results").and_then(Value::as_array),
        v["current_page"].as_u64(),
        v["total_pages"].as_u64(),
    ) {
        let ids = entries
            .iter()
            .filter(|e| {
                e["consumer_appid"].as_u64() == Some(294100)
                    || e["consumer_appid"].as_str() == Some("294100")
            })
            .filter_map(|e| {
                e["publishedfileid"]
                    .as_str()
                    .and_then(|s| storage::id(s).ok())
                    .map(str::to_owned)
            })
            .collect();
        return Some((ids, page < pages));
    }
    match v {
        Value::String(s)
            if s.contains("current_page") && s.trim_start().starts_with(['{', '[']) =>
        {
            results(&serde_json::from_str(s).ok()?, depth + 1)
        }
        Value::Object(o) => o.values().find_map(|child| results(child, depth + 1)),
        Value::Array(a) => a.iter().find_map(|child| results(child, depth + 1)),
        _ => None,
    }
}
fn parse_page(html: &str, page: u32) -> Result<(Vec<String>, bool)> {
    let doc = Html::parse_document(html);
    if let Some(script) = doc
        .select(&Selector::parse("#valve-ssr-data").unwrap())
        .next()
    {
        if let Ok(json) = serde_json::from_str(&script.inner_html()) {
            if let Some(r) = results(&json, 0) {
                return Ok(r);
            }
        }
    }
    let mut ids = Vec::new();
    let mut seen = HashSet::new();
    for a in doc.select(&Selector::parse("a[href*='sharedfiles/filedetails']").unwrap()) {
        if let Some(s) = a
            .value()
            .attr("href")
            .and_then(|s| direct(s).ok().flatten())
        {
            if seen.insert(s.clone()) {
                ids.push(s);
            }
        }
    }
    if ids.is_empty() {
        ensure!(
            doc.root_element()
                .text()
                .any(|s| s.trim() == "0 entries matching filters")
                || html.contains("No items matching your search criteria were found"),
            "工坊搜索页结构已变化或暂时不可用，可直接粘贴条目链接"
        );
        return Ok((ids, false));
    }
    let next = (page + 1).to_string();
    let has_next = doc
        .select(&Selector::parse("a[href]").unwrap())
        .filter_map(|e| e.value().attr("href"))
        .filter_map(|href| {
            reqwest::Url::parse("https://steamcommunity.com")
                .ok()?
                .join(href)
                .ok()
        })
        .any(|u| {
            u.path().contains("/workshop/browse")
                && u.query_pairs().any(|(k, v)| k == "p" && v == next)
        });
    Ok((ids, has_next))
}
#[derive(Deserialize)]
struct Reply {
    response: Details,
}
#[derive(Deserialize)]
struct Details {
    publishedfiledetails: Vec<Entry>,
}
#[derive(Deserialize)]
#[serde(default)]
#[derive(Default)]
struct Entry {
    publishedfileid: String,
    result: u32,
    consumer_app_id: u32,
    title: String,
    preview_url: String,
    description: String,
    time_updated: i64,
    file_type: u32,
}
pub fn search(query: &str, page: u32) -> Result<SearchPage> {
    let client = client(Duration::from_secs(30))?;
    let q = query.trim();
    let page = page.clamp(1, 100000);
    let direct_id = direct(q)?;
    let is_direct = direct_id.is_some();
    let (ids, has_next) = if let Some(id) = direct_id {
        (vec![id], false)
    } else {
        let body = client
            .get("https://steamcommunity.com/workshop/browse/")
            .query(&[
                ("appid", "294100"),
                ("searchtext", q),
                ("p", &page.to_string()),
                ("l", "english"),
                ("browsesort", "textsearch"),
                ("section", "readytouseitems"),
            ])
            .send()
            .context("连接 Steam 工坊失败")?
            .error_for_status()?
            .text()?;
        parse_page(&body, page)?
    };
    if ids.is_empty() {
        return Ok(SearchPage {
            items: vec![],
            has_next,
        });
    }
    let mut form = vec![("itemcount".to_owned(), ids.len().to_string())];
    for (i, id) in ids.iter().enumerate() {
        form.push((format!("publishedfileids[{i}]"), id.clone()));
    }
    let reply: Reply = client
        .post("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")
        .form(&form)
        .send()
        .context("读取工坊详情失败")?
        .error_for_status()?
        .json()
        .context("工坊详情格式异常")?;
    let items = reply
        .response
        .publishedfiledetails
        .into_iter()
        .filter(|e| e.result == 1 && e.consumer_app_id == 294100 && e.file_type != 2)
        .map(|e| WorkshopItem {
            id: e.publishedfileid,
            title: e.title,
            preview: e.preview_url,
            description: e.description,
            updated: e.time_updated,
        })
        .collect::<Vec<_>>();
    if is_direct && items.is_empty() {
        bail!("该条目不可访问、属于其他游戏，或是合集");
    }
    Ok(SearchPage { items, has_next })
}
