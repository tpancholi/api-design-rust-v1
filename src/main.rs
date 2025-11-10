use std::net::TcpListener;
use api_design_rust_v1::run;

#[tokio::main]
async fn main() -> Result<(), std::io::Error> {
    let listener = TcpListener::bind("127.0.0.1:8000").expect("Failed to start server");
    run(listener)?.await
}
