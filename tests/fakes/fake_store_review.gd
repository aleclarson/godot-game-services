extends Node

signal reviewFlowCompleted(succeeded: bool, error_code: int, message: String)

var calls: Array[Dictionary] = []
var request_error: int = OK
var open_page_error: int = OK


func request_in_app_review() -> int:
	calls.append({"method": "request_in_app_review", "arguments": []})
	return request_error


func requestInAppReview() -> int:
	calls.append({"method": "requestInAppReview", "arguments": []})
	return request_error


func open_store_review_page(url: String) -> int:
	calls.append({"method": "open_store_review_page", "arguments": [url]})
	return open_page_error


func openStoreReviewPage(url: String) -> int:
	calls.append({"method": "openStoreReviewPage", "arguments": [url]})
	return open_page_error
