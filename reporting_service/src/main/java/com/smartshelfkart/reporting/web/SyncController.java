package com.smartshelfkart.reporting.web;

import com.smartshelfkart.reporting.security.CallerPrincipal;
import com.smartshelfkart.reporting.sync.FirestoreSyncService;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Rebuilds the caller's projection on demand.
 *
 * <p>There is no company parameter, by design. The workspace comes from the
 * authenticated principal, so this endpoint cannot be pointed at someone else's
 * data however it is called.
 *
 * <p>It requires an administrative grant rather than the reporting one. A
 * rebuild reads every invoice in a workspace and holds a transaction while it
 * writes them back; that is not something a viewer should be able to trigger in
 * a loop.
 */
@RestController
@RequestMapping("/api/sync")
public class SyncController {

    private final FirestoreSyncService sync;

    public SyncController(FirestoreSyncService sync) {
        this.sync = sync;
    }

    @PostMapping
    @PreAuthorize("hasAuthority('canManageCompanySettings') or hasAuthority('*')")
    public FirestoreSyncService.SyncResult rebuild(
            @AuthenticationPrincipal CallerPrincipal caller) {
        return sync.sync(caller.companyId());
    }
}
