use anyhow::Result;
use std::{
    io,
    mem::size_of,
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    process::Child,
    ptr,
};
use windows_sys::Win32::System::JobObjects::*;

/// SteamCMD's bootstrapper can exit with status 7 and hand off to a child.
/// Keep tracking its descendants before committing a staged installation.
pub struct ProcessTree(OwnedHandle);
impl ProcessTree {
    pub fn attach(child: &Child) -> Result<Self> {
        unsafe {
            let job = CreateJobObjectW(ptr::null(), ptr::null());
            if job.is_null() {
                return Err(io::Error::last_os_error().into());
            }
            let owned = OwnedHandle::from_raw_handle(job);
            let mut policy = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
            policy.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if SetInformationJobObject(
                job,
                JobObjectExtendedLimitInformation,
                (&policy as *const _ as *const std::ffi::c_void).cast(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) == 0
                || AssignProcessToJobObject(job, child.as_raw_handle()) == 0
            {
                return Err(io::Error::last_os_error().into());
            }
            Ok(Self(owned))
        }
    }
    pub fn active(&self) -> Result<bool> {
        let mut info = JOBOBJECT_BASIC_ACCOUNTING_INFORMATION::default();
        let ok = unsafe {
            QueryInformationJobObject(
                self.0.as_raw_handle(),
                JobObjectBasicAccountingInformation,
                (&mut info as *mut _ as *mut std::ffi::c_void).cast(),
                size_of::<JOBOBJECT_BASIC_ACCOUNTING_INFORMATION>() as u32,
                ptr::null_mut(),
            )
        };
        if ok == 0 {
            return Err(io::Error::last_os_error().into());
        }
        Ok(info.ActiveProcesses != 0)
    }
}
