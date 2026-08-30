/*************************************************************************/
/*  store_review_module.cpp                                              */
/*************************************************************************/

#include "store_review_module.h"

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/config/engine.h"
#else
#include "core/engine.h"
#endif

#include "store_review.h"

StoreReview *store_review;

void register_storereview_types() {
	store_review = memnew(StoreReview);
	Engine::get_singleton()->add_singleton(Engine::Singleton("StoreReview", store_review));
}

void unregister_storereview_types() {
	if (store_review) {
		memdelete(store_review);
		store_review = NULL;
	}
}
