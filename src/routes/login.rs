use actix_web::{HttpResponse, web};
#[allow(dead_code)]
#[derive(serde::Deserialize)]
pub struct FormData {
    email: String,
    password: String,
}

pub async fn login(_form: web::Form<FormData>) -> HttpResponse {
    HttpResponse::Ok().finish()
}
