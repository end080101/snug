import RemoteCrossDesk
import Testing

@Suite("CrossDesk 判在场：看「共享桌面」电源断言")
struct CrossDeskRemoteTests {
    @Test("只认名字完全一样的断言，持有的进程按号排；别的断言（系统、UU 的防休眠）不算")
    func owners() {
        let assertions: [Int32: [String]] = [
            903: ["UURemote Disable Idle System Sleep"],
            352: ["Powerd - Prevent sleep while display is on"],
            78275: ["CrossDesk is sharing the desktop", "CrossDesk is sharing the desktop"],
            12: ["CrossDesk is sharing the desktop"],
            40: ["CrossDesk is sharing"],
        ]
        #expect(CrossDeskRemote.sharingOwners(in: assertions) == [12, 78275])
        #expect(CrossDeskRemote.sharingOwners(in: [:]).isEmpty)
    }

    @Test("信号快照写清有没有、谁持有、查不了")
    func evidence() {
        #expect(CrossDeskRemote.observation(sharing: [12, 78275]).evidence == "共享断言=有（进程 12、78275）")
        #expect(CrossDeskRemote.observation(sharing: []).evidence == "共享断言=无")
        #expect(CrossDeskRemote.observation(sharing: nil).evidence == "共享断言=查不了")
    }
}
