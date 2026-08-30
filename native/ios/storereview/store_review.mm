/*************************************************************************/
/*  store_review.mm                                                      */
/*************************************************************************/

#include "store_review.h"

#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

StoreReview *StoreReview::instance = NULL;

static UIWindowScene *store_review_active_scene() {
	UIApplication *application = [UIApplication sharedApplication];
	UIWindowScene *fallback_scene = nil;
	for (UIScene *scene in application.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		UIWindowScene *window_scene = (UIWindowScene *)scene;
		if (window_scene.activationState == UISceneActivationStateForegroundActive) {
			for (UIWindow *window in window_scene.windows) {
				if (window.isKeyWindow) {
					return window_scene;
				}
			}
			fallback_scene = window_scene;
		}
	}
	return fallback_scene;
}

void StoreReview::_bind_methods() {
	ClassDB::bind_method(D_METHOD("request_in_app_review"), &StoreReview::request_in_app_review);
	ClassDB::bind_method(D_METHOD("open_store_review_page", "url"), &StoreReview::open_store_review_page);
}

Error StoreReview::request_in_app_review() {
	__block Error result = ERR_UNAVAILABLE;
	void (^request_block)(void) = ^{
		UIWindowScene *scene = store_review_active_scene();
		if (scene == nil) {
			result = ERR_UNAVAILABLE;
			return;
		}

		// StoreKit owns eligibility and may suppress the prompt. This method only
		// reports whether the native request was handed to StoreKit.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
		[SKStoreReviewController requestReviewInScene:scene];
#pragma clang diagnostic pop
		result = OK;
	};

	if ([NSThread isMainThread]) {
		request_block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), request_block);
	}
	return result;
}

Error StoreReview::open_store_review_page(String p_url) {
	if (p_url.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}

	NSString *url_string = [[NSString alloc] initWithUTF8String:p_url.utf8().get_data()];
	NSURL *url = [NSURL URLWithString:url_string];
	if (url == nil || url.scheme == nil) {
		return ERR_INVALID_PARAMETER;
	}

	if ([NSThread isMainThread]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
		});
	}
	return OK;
}

StoreReview *StoreReview::get_singleton() {
	return instance;
}

StoreReview::StoreReview() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
}

StoreReview::~StoreReview() {
	instance = NULL;
}
