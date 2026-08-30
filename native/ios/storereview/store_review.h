/*************************************************************************/
/*  store_review.h                                                       */
/*************************************************************************/

#ifndef STORE_REVIEW_H
#define STORE_REVIEW_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

class StoreReview : public Object {
	GDCLASS(StoreReview, Object);

	static StoreReview *instance;
	static void _bind_methods();

public:
	Error request_in_app_review();
	Error open_store_review_page(String p_url);

	static StoreReview *get_singleton();

	StoreReview();
	~StoreReview();
};

#endif
