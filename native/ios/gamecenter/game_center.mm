/*************************************************************************/
/*  game_center.mm                                                       */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "game_center.h"

#import "game_center_delegate.h"

#if VERSION_MAJOR == 4
#if VERSION_MINOR >= 6
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/godot_view_controller.h"
#elif VERSION_MINOR >= 5
#import "drivers/apple_embedded/godot_app_delegate.h"
#import "drivers/apple_embedded/view_controller.h"
#else
#import "platform/ios/app_delegate.h"
#import "platform/ios/view_controller.h"
#endif
#else
#import "platform/iphone/app_delegate.h"
#import "platform/iphone/view_controller.h"
#endif

#import <GameKit/GameKit.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
typedef PackedInt32Array GodotIntArray;
typedef PackedFloat32Array GodotFloatArray;
typedef PackedByteArray GodotByteArray;
#else
typedef PoolStringArray GodotStringArray;
typedef PoolIntArray GodotIntArray;
typedef PoolRealArray GodotFloatArray;
typedef PoolByteArray GodotByteArray;
#endif

GameCenter *GameCenter::instance = NULL;
GodotGameCenterDelegate *gameCenterDelegate = nil;
NSMutableDictionary<NSString *, NSArray<GKSavedGame *> *> *savedGameConflicts = nil;

static GodotByteArray game_center_bytes_from_data(NSData *p_data) {
	GodotByteArray bytes;
	if (p_data == nil || p_data.length == 0) {
		return bytes;
	}
	bytes.resize(p_data.length);
	memcpy(bytes.ptrw(), p_data.bytes, p_data.length);
	return bytes;
}

static NSData *game_center_data_from_bytes(const GodotByteArray &p_bytes) {
	if (p_bytes.is_empty()) {
		return [NSData data];
	}
	return [NSData dataWithBytes:p_bytes.ptr() length:p_bytes.size()];
}

static Dictionary game_center_saved_game_metadata(GKSavedGame *p_game) {
	Dictionary metadata;
	NSString *name = p_game.name ?: @"";
	NSString *device_name = p_game.deviceName ?: @"";
	int64_t updated_at_msec = p_game.modificationDate == nil ? 0 : (int64_t)(p_game.modificationDate.timeIntervalSince1970 * 1000.0);
	metadata["id"] = [name UTF8String];
	metadata["name"] = [name UTF8String];
	metadata["device_name"] = [device_name UTF8String];
	metadata["updated_at_msec"] = updated_at_msec;
	return metadata;
}

static void game_center_load_saved_games(NSArray<GKSavedGame *> *p_games, void (^p_completion)(Array)) {
	__block Array payloads;
	payloads.resize(p_games.count);
	if (p_games.count == 0) {
		p_completion(payloads);
		return;
	}

	dispatch_group_t group = dispatch_group_create();
	for (NSUInteger index = 0; index < p_games.count; index++) {
		GKSavedGame *game = p_games[index];
		dispatch_group_enter(group);
		[game loadDataWithCompletionHandler:^(NSData *data, NSError *error) {
			Dictionary payload = game_center_saved_game_metadata(game);
			if (error == nil) {
				payload["data"] = game_center_bytes_from_data(data);
			} else {
				payload["error_code"] = (int64_t)error.code;
				payload["error_description"] = [error.localizedDescription UTF8String];
			}
			payloads[index] = payload;
			dispatch_group_leave(group);
		}];
	}

	dispatch_group_notify(group, dispatch_get_main_queue(), ^{
		p_completion(payloads);
	});
}

void GameCenter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("authenticate"), &GameCenter::authenticate);
	ClassDB::bind_method(D_METHOD("is_authenticated"), &GameCenter::is_authenticated);

	ClassDB::bind_method(D_METHOD("post_score"), &GameCenter::post_score);
	ClassDB::bind_method(D_METHOD("award_achievement", "achievement"), &GameCenter::award_achievement);
	ClassDB::bind_method(D_METHOD("reset_achievements"), &GameCenter::reset_achievements);
	ClassDB::bind_method(D_METHOD("request_achievements"), &GameCenter::request_achievements);
	ClassDB::bind_method(D_METHOD("request_achievement_descriptions"), &GameCenter::request_achievement_descriptions);
	ClassDB::bind_method(D_METHOD("show_game_center"), &GameCenter::show_game_center);
	ClassDB::bind_method(D_METHOD("request_identity_verification_signature"), &GameCenter::request_identity_verification_signature);
	ClassDB::bind_method(D_METHOD("save_game", "save"), &GameCenter::save_game);
	ClassDB::bind_method(D_METHOD("load_game", "name"), &GameCenter::load_game);
	ClassDB::bind_method(D_METHOD("list_saved_games"), &GameCenter::list_saved_games);
	ClassDB::bind_method(D_METHOD("delete_saved_game", "name"), &GameCenter::delete_saved_game);
	ClassDB::bind_method(D_METHOD("resolve_saved_game_conflict", "resolution"), &GameCenter::resolve_saved_game_conflict);

	ClassDB::bind_method(D_METHOD("get_pending_event_count"), &GameCenter::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"), &GameCenter::pop_pending_event);
};

Error GameCenter::authenticate() {
	//if this class isn't available, game center isn't implemented
	if ((NSClassFromString(@"GKLocalPlayer")) == nil) {
		return ERR_UNAVAILABLE;
	}

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	ERR_FAIL_COND_V(![player respondsToSelector:@selector(authenticateHandler)], ERR_UNAVAILABLE);

	UIViewController *root_controller = [[UIApplication sharedApplication] delegate].window.rootViewController;
	ERR_FAIL_COND_V(!root_controller, FAILED);

	// This handler is called several times.  First when the view needs to be shown, then again
	// after the view is cancelled or the user logs in.  Or if the user's already logged in, it's
	// called just once to confirm they're authenticated.  This is why no result needs to be specified
	// in the presentViewController phase. In this case, more calls to this function will follow.
	_weakify(root_controller);
	_weakify(player);
	player.authenticateHandler = (^(UIViewController *controller, NSError *error) {
		_strongify(root_controller);
		_strongify(player);

		if (controller) {
			[root_controller presentViewController:controller animated:YES completion:nil];
		} else {
			Dictionary ret;
			ret["type"] = "authentication";
			if (player.isAuthenticated) {
				ret["result"] = "ok";
				ret["alias"] = [player.alias UTF8String];
				ret["displayName"] = [player.displayName UTF8String];

				ret["player_id"] = [player.teamPlayerID UTF8String];

				GameCenter::get_singleton()->authenticated = true;
			} else {
				ret["result"] = "error";
				ret["error_code"] = error == nil ? 0 : (int64_t)error.code;
				ret["error_description"] = error == nil ? "Player is not authenticated" : [error.localizedDescription UTF8String];
				GameCenter::get_singleton()->authenticated = false;
			};

			pending_events.push_back(ret);
		};
	});

	return OK;
};

bool GameCenter::is_authenticated() {
	return authenticated;
};

Error GameCenter::post_score(Dictionary p_score) {
	ERR_FAIL_COND_V(!p_score.has("score") || !p_score.has("category"), ERR_INVALID_PARAMETER);
	int64_t score = p_score["score"];
	String category = p_score["category"];

	NSString *cat_str = [[NSString alloc] initWithUTF8String:category.utf8().get_data()];
	[GKLeaderboard submitScore:score
					 context:0
					  player:[GKLocalPlayer localPlayer]
			 leaderboardIDs:@[ cat_str ]
			 completionHandler:^(NSError *error) {
				Dictionary ret;
				ret["type"] = "post_score";
				ret["platform_id"] = category;
				if (error == nil) {
					ret["result"] = "ok";
				} else {
					ret["result"] = "error";
					ret["error_code"] = (int64_t)error.code;
					ret["error_description"] = [error.localizedDescription UTF8String];
				};

				pending_events.push_back(ret);
			}];

	return OK;
};

Error GameCenter::award_achievement(Dictionary p_params) {
	ERR_FAIL_COND_V(!p_params.has("name") || !p_params.has("progress"), ERR_INVALID_PARAMETER);
	String name = p_params["name"];
	float progress = p_params["progress"];

	NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
	GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:name_str];
	ERR_FAIL_COND_V(!achievement, FAILED);

	ERR_FAIL_COND_V([GKAchievement respondsToSelector:@selector(reportAchievements)], ERR_UNAVAILABLE);

	achievement.percentComplete = progress;
	achievement.showsCompletionBanner = NO;
	if (p_params.has("show_completion_banner")) {
		achievement.showsCompletionBanner = p_params["show_completion_banner"] ? YES : NO;
	}

	[GKAchievement reportAchievements:@[ achievement ]
				withCompletionHandler:^(NSError *error) {
					Dictionary ret;
					ret["type"] = "award_achievement";
					ret["platform_id"] = name;
					if (error == nil) {
						ret["result"] = "ok";
					} else {
						ret["result"] = "error";
						ret["error_code"] = (int64_t)error.code;
					};

					pending_events.push_back(ret);
				}];

	return OK;
};

void GameCenter::request_achievement_descriptions() {
	[GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:^(NSArray *descriptions, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievement_descriptions";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotStringArray titles;
			GodotStringArray unachieved_descriptions;
			GodotStringArray achieved_descriptions;
			GodotIntArray maximum_points;
			Array hidden;
			Array replayable;

			for (NSUInteger i = 0; i < [descriptions count]; i++) {

				GKAchievementDescription *description = [descriptions objectAtIndex:i];

				const char *str = [description.identifier UTF8String];
				names.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.title UTF8String];
				titles.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.unachievedDescription UTF8String];
				unachieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

				str = [description.achievedDescription UTF8String];
				achieved_descriptions.push_back(String::utf8(str != NULL ? str : ""));

				maximum_points.push_back(description.maximumPoints);

				hidden.push_back(description.hidden == YES);

				replayable.push_back(description.replayable == YES);
			}

			ret["names"] = names;
			ret["titles"] = titles;
			ret["unachieved_descriptions"] = unachieved_descriptions;
			ret["achieved_descriptions"] = achieved_descriptions;
			ret["maximum_points"] = maximum_points;
			ret["hidden"] = hidden;
			ret["replayable"] = replayable;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::request_achievements() {
	[GKAchievement loadAchievementsWithCompletionHandler:^(NSArray *achievements, NSError *error) {
		Dictionary ret;
		ret["type"] = "achievements";
		if (error == nil) {
			ret["result"] = "ok";
			GodotStringArray names;
			GodotFloatArray percentages;

			for (NSUInteger i = 0; i < [achievements count]; i++) {

				GKAchievement *achievement = [achievements objectAtIndex:i];
				const char *str = [achievement.identifier UTF8String];
				names.push_back(String::utf8(str != NULL ? str : ""));

				percentages.push_back(achievement.percentComplete);
			}

			ret["names"] = names;
			ret["progress"] = percentages;

		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

void GameCenter::reset_achievements() {
	[GKAchievement resetAchievementsWithCompletionHandler:^(NSError *error) {
		Dictionary ret;
		ret["type"] = "reset_achievements";
		if (error == nil) {
			ret["result"] = "ok";
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
		};

		pending_events.push_back(ret);
	}];
};

Error GameCenter::show_game_center(Dictionary p_params) {
	ERR_FAIL_COND_V(!NSProtocolFromString(@"GKGameCenterControllerDelegate"), FAILED);

	GKGameCenterViewControllerState view_state = GKGameCenterViewControllerStateDefault;
	if (p_params.has("view")) {
		String view_name = p_params["view"];
		if (view_name == "default") {
			view_state = GKGameCenterViewControllerStateDefault;
		} else if (view_name == "leaderboards") {
			view_state = GKGameCenterViewControllerStateLeaderboards;
		} else if (view_name == "achievements") {
			view_state = GKGameCenterViewControllerStateAchievements;
		} else if (view_name == "challenges") {
			view_state = GKGameCenterViewControllerStateChallenges;
		} else {
			return ERR_INVALID_PARAMETER;
		}
	}

	GKGameCenterViewController *controller = nil;
	if (view_state == GKGameCenterViewControllerStateLeaderboards && p_params.has("leaderboard_name")) {
		String name = p_params["leaderboard_name"];
		NSString *name_str = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
		controller = [[GKGameCenterViewController alloc]
				initWithLeaderboardID:name_str
						 playerScope:GKLeaderboardPlayerScopeGlobal
						   timeScope:GKLeaderboardTimeScopeAllTime];
	} else {
		controller = [[GKGameCenterViewController alloc] initWithState:view_state];
	}
	ERR_FAIL_COND_V(!controller, FAILED);

	UIViewController *root_controller = [[UIApplication sharedApplication] delegate].window.rootViewController;
	ERR_FAIL_COND_V(!root_controller, FAILED);

	controller.gameCenterDelegate = gameCenterDelegate;

	[root_controller presentViewController:controller animated:YES completion:nil];

	return OK;
};

Error GameCenter::request_identity_verification_signature() {
	ERR_FAIL_COND_V(!is_authenticated(), ERR_UNAUTHORIZED);

	GKLocalPlayer *player = [GKLocalPlayer localPlayer];
	void (^verificationSignatureHandler)(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) = ^(NSURL *publicKeyUrl, NSData *signature, NSData *salt, uint64_t timestamp, NSError *error) {
		Dictionary ret;
		ret["type"] = "identity_verification_signature";
		if (error == nil) {
			ret["result"] = "ok";
			ret["public_key_url"] = [publicKeyUrl.absoluteString UTF8String];
			ret["signature"] = [[signature base64EncodedStringWithOptions:0] UTF8String];
			ret["salt"] = [[salt base64EncodedStringWithOptions:0] UTF8String];
			ret["timestamp"] = timestamp;
			ret["player_id"] = [player.teamPlayerID UTF8String];
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		};

		pending_events.push_back(ret);
	};

	[player fetchItemsForIdentityVerificationSignature:verificationSignatureHandler];

	return OK;
};

Error GameCenter::save_game(Dictionary p_params) {
	ERR_FAIL_COND_V(!is_authenticated(), ERR_UNAUTHORIZED);
	ERR_FAIL_COND_V(!p_params.has("name") || !p_params.has("data"), ERR_INVALID_PARAMETER);

	String name = p_params["name"];
	GodotByteArray data = p_params["data"];
	NSString *native_name = [[NSString alloc] initWithUTF8String:name.utf8().get_data()];
	[[GKLocalPlayer localPlayer] saveGameData:game_center_data_from_bytes(data)
							withName:native_name
					 completionHandler:^(GKSavedGame *saved_game, NSError *error) {
						 Dictionary ret;
						 ret["type"] = "save_game";
						 ret["name"] = name;
						 if (error == nil && saved_game != nil) {
							 ret["result"] = "ok";
							 ret["saved_game"] = game_center_saved_game_metadata(saved_game);
						 } else {
							 ret["result"] = "error";
							 ret["error_code"] = error == nil ? 0 : (int64_t)error.code;
							 ret["error_description"] = error == nil ? "Game Center returned no saved game" : [error.localizedDescription UTF8String];
						 }
						 pending_events.push_back(ret);
					 }];
	return OK;
}

void GameCenter::load_game(String p_name) {
	NSString *native_name = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];
	[[GKLocalPlayer localPlayer] fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *games, NSError *error) {
		if (error != nil) {
			Dictionary ret;
			ret["type"] = "load_game";
			ret["name"] = p_name;
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
			pending_events.push_back(ret);
			return;
		}

		NSMutableArray<GKSavedGame *> *matches = [NSMutableArray array];
		for (GKSavedGame *game in games) {
			if ([game.name isEqualToString:native_name]) {
				[matches addObject:game];
			}
		}

		if (matches.count == 0) {
			Dictionary ret;
			ret["type"] = "load_game";
			ret["name"] = p_name;
			ret["result"] = "not_found";
			ret["error_description"] = "Saved game not found";
			pending_events.push_back(ret);
			return;
		}

		if (matches.count > 1) {
			NSString *conflict_id = [NSUUID UUID].UUIDString;
			savedGameConflicts[conflict_id] = [matches copy];
			game_center_load_saved_games(matches, ^(Array payloads) {
				Dictionary ret;
				ret["type"] = "load_game";
				ret["name"] = p_name;
				ret["result"] = "conflict";
				ret["conflict_id"] = [conflict_id UTF8String];
				ret["saved_games"] = payloads;
				pending_events.push_back(ret);
			});
			return;
		}

		GKSavedGame *game = matches.firstObject;
		[game loadDataWithCompletionHandler:^(NSData *data, NSError *load_error) {
			Dictionary ret;
			ret["type"] = "load_game";
			ret["name"] = p_name;
			if (load_error == nil) {
				ret["result"] = "ok";
				ret["data"] = game_center_bytes_from_data(data);
				ret["saved_game"] = game_center_saved_game_metadata(game);
			} else {
				ret["result"] = "error";
				ret["error_code"] = (int64_t)load_error.code;
				ret["error_description"] = [load_error.localizedDescription UTF8String];
			}
			pending_events.push_back(ret);
		}];
	}];
}

void GameCenter::list_saved_games() {
	[[GKLocalPlayer localPlayer] fetchSavedGamesWithCompletionHandler:^(NSArray<GKSavedGame *> *games, NSError *error) {
		Dictionary ret;
		ret["type"] = "list_saved_games";
		if (error == nil) {
			ret["result"] = "ok";
			Array payloads;
			for (GKSavedGame *game in games) {
				payloads.push_back(game_center_saved_game_metadata(game));
			}
			ret["saved_games"] = payloads;
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		}
		pending_events.push_back(ret);
	}];
}

void GameCenter::delete_saved_game(String p_name) {
	NSString *native_name = [[NSString alloc] initWithUTF8String:p_name.utf8().get_data()];
	[[GKLocalPlayer localPlayer] deleteSavedGamesWithName:native_name completionHandler:^(NSError *error) {
		Dictionary ret;
		ret["type"] = "delete_saved_game";
		ret["name"] = p_name;
		if (error == nil) {
			ret["result"] = "ok";
		} else {
			ret["result"] = "error";
			ret["error_code"] = (int64_t)error.code;
			ret["error_description"] = [error.localizedDescription UTF8String];
		}
		pending_events.push_back(ret);
	}];
}

Error GameCenter::resolve_saved_game_conflict(Dictionary p_params) {
	ERR_FAIL_COND_V(!is_authenticated(), ERR_UNAUTHORIZED);
	ERR_FAIL_COND_V(!p_params.has("conflict_id") || !p_params.has("data"), ERR_INVALID_PARAMETER);

	String conflict_id = p_params["conflict_id"];
	GodotByteArray data = p_params["data"];
	NSString *native_conflict_id = [[NSString alloc] initWithUTF8String:conflict_id.utf8().get_data()];
	NSArray<GKSavedGame *> *games = savedGameConflicts[native_conflict_id];
	ERR_FAIL_COND_V(games == nil, ERR_DOES_NOT_EXIST);

	[[GKLocalPlayer localPlayer] resolveConflictingSavedGames:games
											withData:game_center_data_from_bytes(data)
								 completionHandler:^(NSArray<GKSavedGame *> *resolved_games, NSError *error) {
									 Dictionary ret;
									 ret["type"] = "resolve_saved_game_conflict";
									 ret["conflict_id"] = conflict_id;
									 if (error == nil) {
										 [savedGameConflicts removeObjectForKey:native_conflict_id];
										 ret["result"] = "ok";
										 Array payloads;
										 for (GKSavedGame *game in resolved_games) {
											 payloads.push_back(game_center_saved_game_metadata(game));
										 }
										 ret["saved_games"] = payloads;
									 } else {
										 ret["result"] = "error";
										 ret["error_code"] = (int64_t)error.code;
										 ret["error_description"] = [error.localizedDescription UTF8String];
									 }
									 pending_events.push_back(ret);
								 }];
	return OK;
}

void GameCenter::game_center_closed() {
	Dictionary ret;
	ret["type"] = "show_game_center";
	ret["result"] = "ok";
	pending_events.push_back(ret);
}

int GameCenter::get_pending_event_count() {
	return pending_events.size();
};

Variant GameCenter::pop_pending_event() {
	Variant front = pending_events.front()->get();
	pending_events.pop_front();

	return front;
};

GameCenter *GameCenter::get_singleton() {
	return instance;
};

GameCenter::GameCenter() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	authenticated = false;

	gameCenterDelegate = [[GodotGameCenterDelegate alloc] init];
	savedGameConflicts = [[NSMutableDictionary alloc] init];
};

GameCenter::~GameCenter() {
	if (gameCenterDelegate) {
		gameCenterDelegate = nil;
	}
	if (savedGameConflicts) {
		savedGameConflicts = nil;
	}
}
